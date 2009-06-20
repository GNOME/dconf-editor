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
#include <stdlib.h>
#include <fcntl.h>
#include <glib/gstdio.h>
#include <errno.h>


#include <glib/gvariant.h>
#include <string.h>

void
dconf_writer_allocate (DConfWriter *writer,
                       gsize        size,
                       gpointer    *pointer,
                       guint32     *index)
{
  *index = writer->super->next;

  if (*index + 1 + (size + 7) / 8 <= writer->n_blocks)
    {
      writer->blocks[*index].size = size; 
      *pointer = &writer->blocks[*index + 1];

      writer->super->next += 1 + (size + 7) / 8;
    }
  else
    {
      if (writer->n_extras == writer->extras_size)
        {
          writer->extras_size = MAX (16, writer->extras_size * 2);
          writer->extras = g_renew (gpointer,
                                    writer->extras,
                                    writer->extras_size);
        }

      writer->extra_sizes[writer->n_extras] = size;
      writer->extras[writer->n_extras] = g_malloc (size);
   
      *pointer = writer->extras[writer->n_extras];
      *index = -(writer->n_extras++);
    }
}

static volatile void *
dconf_writer_get_block (DConfWriter *writer,
                        guint32      index,
                        guint32     *size)
{
  g_assert ((index < writer->n_blocks) ^
            (-index < writer->n_extras));

  if (index < writer->n_blocks)
    {
      g_assert (-index >= writer->n_extras);
      *size = writer->blocks[index].size;
      return &writer->blocks[index + 1];
    }
  else
    {
      g_assert (-index < writer->n_extras);
      *size = writer->extra_sizes[-index];
      return writer->extras[-index];
    }
}

volatile struct dir_entry *
dconf_writer_get_dir (DConfWriter *writer,
                      guint32      index,
                      gint        *length)
{
  volatile struct dir_entry *entries;
  guint32 size;

  if (index == 0)
    {
      *length = 0;
      return NULL;
    }

  entries = dconf_writer_get_block (writer, index, &size);
  g_assert_cmpint (size % sizeof (struct dir_entry), ==, 0);

  *length = size / sizeof (struct dir_entry);

  return entries;
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

  g_assert (buf.st_size % 4096 == 0);
  writer->n_blocks = buf.st_size / 8;

  contents = mmap (NULL, buf.st_size,
                   PROT_READ | PROT_WRITE,
                   MAP_SHARED, fd, 0);

  writer->super = contents;
  writer->blocks = contents;

  return TRUE;
}

/*
static void
dconf_writer_invalid_dir (DConfWriter *writer,
                          guint32     *index)
{
  struct dir_entry *entry;
  gpointer pointer;

  dconf_writer_allocate (writer, sizeof (struct dir_entry),
                         &pointer, index);

  entry = pointer;

  entry->type = 'b';
  entry->namelen = 8;
  entry->locked = FALSE;
  strcpy (entry->name.direct, ".invalid");
  entry->data.direct = 0;
}

static void
dconf_writer_copy_block (DConfWriter *writer,
                         DConfWriter *src,
                         guint32      src_index,
                         guint32     *index)
{
  static volatile void *old_pointer;
  gpointer pointer;
  gsize size;

  old_pointer = dconf_writer_get_block (src, src_index, &size);

  dconf_writer_allocate (writer, size, &pointer, index);

  memcpy (pointer, (gconstpointer) old_pointer, size);
}

static void
dconf_writer_copy_directory (DConfWriter *writer,
                             DConfWriter *src,
                             guint32      src_index,
                             guint32     *index)
{
  volatile struct dir_entry *old_entries;
  struct dir_entry *entries;
  gpointer pointer;
  gint length;
  gint i;

  old_entries = dconf_writer_get_dir (src, src_index, &length);

  if (old_entries == NULL)
    {
      dconf_writer_invalid_dir (writer, index);
      return;
    }

  dconf_writer_allocate (writer,
                         length * sizeof (struct dir_entry),
                         &pointer, index);

  entries = pointer;

  for (i = 0; i < length; i++)
    {
      entries[i] = old_entries[i];

      if (entries[i].type == '/')
        {
          dconf_writer_copy_directory (writer, src,
                                       entries[i].data.index,
                                       &entries[i].data.index);
        }
      else if (entries[i].type == 'v')
        {
          dconf_writer_copy_block (writer, src,
                                   entries[i].data.index,
                                   &entries[i].data.index);
        }
    }
}
*/

static gboolean
dconf_writer_create (DConfWriter *writer)
{
  /* the sun came up
   * shot through the blinds
   *
   * today was the day
   * and i was already behind
   */
  gpointer contents;
  int fd;

  writer->floating = g_strdup_printf ("%s.XXXXXX", writer->filename);

  g_assert (writer->super == NULL);

  /* XXX flink() plz */
  fd = g_mkstemp (writer->floating);
  posix_fallocate (fd, 0, 4096);

  writer->n_blocks = 4096 / 8;
  contents = mmap (NULL, 4096,
                   PROT_READ | PROT_WRITE,
                   MAP_SHARED, fd, 0);

  writer->super = contents;
  writer->blocks = contents;
  writer->super->signature[0] = DCONF_SIGNATURE_0;
  writer->super->signature[1] = DCONF_SIGNATURE_1;
  writer->super->next = sizeof (struct superblock) / 8;
  writer->super->root_index = 0;

  return TRUE;
}

static gboolean
dconf_writer_post (DConfWriter  *writer,
                   GError      **error)
{
  if (g_rename (writer->floating, writer->filename))
    {
      gint saved_error = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_error),
                   "rename '%s' to '%s': %s",
                   writer->floating, writer->filename,
                   g_strerror (saved_error));

      return FALSE;
    }

  g_free (writer->floating);
  writer->floating = NULL;

  return TRUE;
}

DConfWriter *
dconf_writer_new (const gchar *filename)
{
  DConfWriter *writer;

  writer = g_slice_new (DConfWriter);
  writer->filename = g_strdup (filename);
  writer->super = NULL;
  writer->floating = NULL;

  if (dconf_writer_open (writer))
    return writer;

  if (!dconf_writer_create (writer))
    g_assert_not_reached ();

  if (!dconf_writer_post (writer, NULL))
    g_error ("could not post\n");

  return writer;
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

void
dconf_writer_set_entry_index (DConfWriter               *writer,
                              volatile struct dir_entry *entry,
                              guint32                    index,
                              gboolean                   blind_write)
{
  if (blind_write || writer->extras == NULL)
    {
      if (entry->data.index != index)
        entry->data.index = index;
    }

  g_assert (writer->changed_entry == NULL);
  writer->changed_entry = entry;
  writer->changed_index = index;
}

guint32
dconf_writer_get_entry_index (DConfWriter               *writer,
                              volatile struct dir_entry *entry,
                              gboolean                   for_copy)
{
  if G_UNLIKELY (writer->changed_entry == entry)
    {
      g_assert (for_copy);

      return writer->changed_index;
    }

  return entry->data.index;
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

      dconf_writer_allocate (writer, name_length, &pointer, &index);
      memcpy (pointer, name, name_length);
      entry->name.index = index;
    }
  else
    {
      memcpy ((gchar *) entry->name.direct, name, name_length);
      entry->namelen = name_length;
    }
}
