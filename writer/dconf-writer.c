/*
 * Copyright © 2009 Codethink Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#include "dconf-writer-private.h"

#include <glib/gvariant-loadstore.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <glib/gstdio.h>
#include <string.h>
#include <errno.h>

static gboolean
dconf_writer_in_bounds (DConfWriter   *writer,
                        volatile void *start,
                        volatile void *end)
{
  g_assert ((gpointer) writer->data.super <= start);
  g_assert (start <= writer->end);

  return start < end && end < writer->end;
}

gpointer
dconf_writer_allocate (DConfWriter *writer,
                       gsize        size,
                       guint32     *index)
{
  struct chunk_header *chunk = (gpointer) (writer->data.blocks + 
                                           writer->data.super->next);

  if (!dconf_writer_in_bounds (writer, chunk, &chunk->contents[size]))
    {
      *index = ~writer->extras->len;
      chunk = g_malloc (sizeof (struct chunk_header) + size);
      g_ptr_array_add (writer->extras, chunk);
    }
  else
    {
      *index = writer->data.super->next;
      writer->data.super->next += 1 + (size + 7) / 8;
    }

  chunk->size = size;

  return chunk->contents;
}

static volatile void *
dconf_writer_get_block (DConfWriter *writer,
                        guint32      index,
                        guint32     *size)
{
  struct chunk_header *chunk = NULL;

  if (~index < index)
    {
      if (~index < writer->extras->len)
        chunk = g_ptr_array_index (writer->extras, ~index);
    }
  else
    {
      if (index >= 4 &&
          dconf_writer_in_bounds (writer,
                                  writer->data.blocks,
                                  &writer->data.blocks[index + 1]))
        {
          struct chunk_header *maybe = &writer->data.blocks[index];

          if (dconf_writer_in_bounds (writer,
                                      maybe->contents,
                                      &maybe->contents[maybe->size]))
            chunk = maybe;
        }
    }

  if (chunk)
    {
      *size = chunk->size;
      return chunk->contents;
    }
  else
    {
      *size = 0;
      return NULL;
    }
}

volatile struct dir_entry *
dconf_writer_get_dir (DConfWriter *writer,
                      guint32      index,
                      gint        *n_items)
{
  volatile struct dir_entry *entries;
  guint32 size;

  entries = dconf_writer_get_block (writer, index, &size);

  if (size % sizeof (struct dir_entry))
    size = 0;

  *n_items = size / sizeof (struct dir_entry);

  return size ? entries : NULL;
}

volatile struct dir_entry *
dconf_writer_find_entry (DConfWriter               *writer,
                         volatile struct dir_entry *entries,
                         gint                       n_entries,
                         const gchar               *name,
                         gint                       name_length)
{
  /* XXX replace with a binary search */
  gint i;

  for (i = 0; i < n_entries; i++)
    {
      const gchar *entry_name;
      guint32 entry_length;

      entry_name = dconf_writer_get_entry_name (writer, &entries[i],
                                                &entry_length);
      if (entry_length == name_length &&
          !memcmp (entry_name, name, name_length))
        return &entries[i];
    }

  return NULL;
}

volatile struct dir_entry *
dconf_writer_next_entry (DConfWriter                *writer,
                         volatile struct dir_entry  *entries,
                         gint                        n_entries,
                         const gchar                *name,
                         const gchar               **next)
{
  gint name_length;

  for (name_length = 0; name[name_length]; name_length++)
    if (name[name_length] == '/')
      {
        name_length++;
        break;
      }

  if (next)
    *next = &name[name_length];

  g_assert (name[0]);

  return dconf_writer_find_entry (writer, entries, n_entries,
                                  name, name_length);
}

void
dconf_writer_set_index (DConfWriter      *writer,
                        volatile guint32 *pointer,
                        guint32           value,
                        gboolean          blind_write)
{
  if (*pointer == value)
    return;

  if (blind_write)
    {
      *pointer = value;
    }
  else
    {
      g_assert (writer->changed_pointer == NULL);
      writer->changed_pointer = pointer;
      writer->changed_value = value;
    }
}

guint32
dconf_writer_get_index (DConfWriter            *writer,
                        const volatile guint32 *pointer,
                        gboolean                for_copy)
{
  /* if we already have a changed pointer then this means that we have
   * (theoretically) visible changes.  so why are we doing more work?
   */
  g_assert (!for_copy || !writer->changed_pointer);

  if G_UNLIKELY (writer->changed_pointer == pointer)
    return writer->changed_value;

  return *pointer;
}

const gchar *
dconf_writer_get_entry_name (DConfWriter                     *writer,
                             const volatile struct dir_entry *entry,
                             guint32                         *name_length)
{
  if G_UNLIKELY (entry->namelen > sizeof entry->name.direct)
    return (const gchar *) dconf_writer_get_block (writer,
                                                   entry->name.index,
                                                   name_length);

  *name_length = entry->namelen;

  return (const gchar *) entry->name.direct;
}

void
dconf_writer_set_entry_name (DConfWriter               *writer,
                             volatile struct dir_entry *entry,
                             const gchar               *name,
                             gint                       name_length)
{
  if G_UNLIKELY (name_length > sizeof entry->name.direct)
    {
      gpointer pointer;
      guint32 index;

      pointer = dconf_writer_allocate (writer, name_length, &index);
      memcpy (pointer, name, name_length);
      entry->name.index = index;
    }
  else
    {
      memcpy ((gchar *) entry->name.direct, name, name_length);
      entry->namelen = name_length;
    }
}



static gboolean
dconf_writer_open (DConfWriter *writer)
{
  gpointer contents;
  struct stat buf;
  gint fd;

  fd = open (writer->filename, O_RDWR);

  if (fd < 0)
    return FALSE;

  if (fstat (fd, &buf))
    {
      g_assert_not_reached ();
      close (fd);

      return FALSE;
    }

  g_assert (buf.st_size % 4194304 == 0);

  contents = mmap (NULL, buf.st_size,
                   PROT_READ | PROT_WRITE,
                   MAP_SHARED, fd, 0);

  writer->data.super = contents;
  writer->end = &writer->data.blocks[buf.st_size / 8];

  return TRUE;
}

DConfWriter *
dconf_writer_new (const gchar  *filename,
                  GError      **error)
{
  DConfWriter *writer;

  writer = g_slice_new (DConfWriter);
  writer->filename = g_strdup (filename);
  writer->extras = g_ptr_array_new ();

  writer->changed_pointer = NULL;
  writer->changed_value = 0;
  writer->data.super = NULL;
  writer->end = NULL;

  if (dconf_writer_open (writer))
    return writer;

  if (!dconf_writer_create (writer, error))
    return NULL;

  return writer;
}

gboolean
dconf_writer_set (DConfWriter  *writer,
                  const gchar  *key,
                  GVariant     *value,
                  GError      **error)
{
  const gchar *empty_string = "";

  return dconf_writer_merge (writer, key, &empty_string, &value, 1, error);
}
