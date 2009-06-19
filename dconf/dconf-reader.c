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

#include "dconf-reader.h"

#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>

#include <glib/gvariant-loadstore.h>
#include <glib.h>

#include "dconf-format.h"

struct OPAQUE_TYPE__DConfReader
{
  GMappedFile *mapped_file;
  gchar *filename;

  union
  {
    const volatile struct superblock *super;
    const volatile struct block_header *blocks;
  } data;

  const volatile void *end;
};

typedef const volatile struct dir_entry de;

DConfReader *
dconf_reader_new (const gchar *filename)
{
  DConfReader *reader;

  reader = g_slice_new0 (DConfReader);
  reader->filename = g_strdup (filename);

  return reader;
}

static gboolean
dconf_reader_ensure_valid (DConfReader *reader)
{
  if (reader->data.super && reader->data.super->invalid)
    {
      g_mapped_file_unref (reader->mapped_file);
      reader->mapped_file = NULL;
      reader->data.super = NULL;
      reader->end = NULL;
    }

  if (reader->mapped_file == NULL)
    {
      const volatile struct superblock *super;
      const volatile gchar *data;
      GMappedFile *mapped_file;
      gsize size;

      mapped_file = g_mapped_file_new (reader->filename, FALSE, NULL);

      if (mapped_file == NULL)
        return FALSE;

      data = g_mapped_file_get_contents (mapped_file);
      size = g_mapped_file_get_length (mapped_file);

      if (size < 4096)
        {
          g_mapped_file_unref (mapped_file);
          return FALSE;
        }

      super = (struct superblock *) data;
      if (super->signature[0] != DCONF_SIGNATURE_0 ||
          super->signature[1] != DCONF_SIGNATURE_1)
        {
          g_mapped_file_unref (mapped_file);
          return FALSE;
        }

      reader->mapped_file = mapped_file;
      reader->data.super = super;
      reader->end = data + size;
    }

  return TRUE;
}

static gboolean
dconf_reader_past_end (DConfReader         *reader,
                       const volatile void *item)
{
  return (gpointer) item > reader->end;
}

static const volatile void *
dconf_reader_get_block (DConfReader *reader,
                        guint32      index,
                        guint32     *size)
{
  const volatile struct block_header *header;

  header = &reader->data.blocks[index];

  if (dconf_reader_past_end (reader, header + 1))
    return NULL;

  header = &reader->data.blocks[index];

  if (header->contents + header->size < header->contents)
    /* size so big that it wraps the pointer value */
    return NULL;

  if (dconf_reader_past_end (reader, header->contents + header->size))
    return NULL;

  *size = header->size;

  return header->contents;
}

static const volatile struct dir_entry *
dconf_reader_get_dir (DConfReader *reader,
                      guint32      index,
                      gint        *n_items)
{
  const volatile struct dir_entry *entries;
  guint32 size;

  if ((entries = dconf_reader_get_block (reader, index, &size)) == NULL)
    {
      *n_items = 0;
      return NULL;
    }

  if (size % sizeof (struct dir_entry))
    {
      *n_items = 0;
      return NULL;
    }

  *n_items = size / sizeof (struct dir_entry);

  return entries;
}

static const volatile gchar *
dconf_reader_get_entry_name (DConfReader                     *reader,
                             const volatile struct dir_entry *entry,
                             guint32                         *name_length)
{
  *name_length = entry->namelen;

  if (*name_length > sizeof entry->name.direct)
    return dconf_reader_get_block (reader, entry->name.index, name_length);
  else
    return entry->name.direct;
}

static const volatile struct dir_entry *
dconf_reader_find_entry (DConfReader                     *reader,
                         const volatile struct dir_entry *entries,
                         gint                             n_entries,
                         const gchar                     *name,
                         gint                             name_length)
{
  gint i;

  for (i = 0; i < n_entries; i++)
    {
      const volatile struct dir_entry *entry = &entries[i];
      const volatile gchar *entry_name;
      guint32 entry_namelen;

      entry_name = dconf_reader_get_entry_name (reader, entry,
                                                &entry_namelen);

      if (entry_name == NULL)
        continue;

      if (entry_namelen == name_length &&
          memcmp ((gchar *) entry_name, name, name_length) == 0)
        return entry;
    }

  return NULL;
}

static const volatile struct dir_entry *
dconf_reader_get_entry (DConfReader *reader,
                        const gchar *name,
                        guint32      starting_index,
                        gboolean    *locked)
{
  const volatile struct dir_entry *entries;
  const volatile struct dir_entry *entry;
  gint n_entries;
  gint namelen;

  entries = dconf_reader_get_dir (reader, starting_index, &n_entries);

  if (entries == NULL)
    return NULL;

  for (namelen = 0; name[namelen]; namelen++)
    if (name[namelen] == '/')
      {
        namelen++;
        break;
      }

  entry = dconf_reader_find_entry (reader, entries, n_entries, name, namelen);

  if (entry == NULL)
    return NULL;

  if (entry->locked)
    *locked = TRUE;

  if (name[namelen] == '\0')
    return entry;

  return dconf_reader_get_entry (reader, name + namelen,
                                 entry->data.index, locked);
}

void
dconf_reader_get (DConfReader  *reader,
                  const gchar  *key,
                  GVariant    **value,
                  gboolean     *locked)
{
  const volatile struct dir_entry *entry;
  guint32 index;
  char type;

  g_assert (key[0]);

  if (!dconf_reader_ensure_valid (reader))
    return;

  index = reader->data.super->root_index;
  entry = dconf_reader_get_entry (reader, key, index, locked);

  if (entry == NULL)
    return;

  type = entry->type;

  if (*value)
    g_variant_unref (*value);

  if (type == 'v')
    {
      const volatile void *data;
      gsize size;

      data = dconf_reader_get_block (reader, entry->data.index, &size);

      if (data)
        *value = g_variant_load (NULL, (gpointer) data, size, 0);
    }

  else
    {
      guint64 data = entry->data.direct;
      gsize size;

      switch (type)
        {
          case 'y': case 'b':
            size = 1;
            break;

          case 'n': case 'q':
            size = 2;
            break;

          case 'i': case 'u':
            size = 4;
            break;

          case 'x': case 't': case 'd':
            size = 8;
            break;

          default:
            g_warning ("dconf: invalid type '%c' for key %s", type, key);
            *value = NULL;
            return;
        }

      *value = g_variant_load ((GVariantType *) &type, &data, size, 0);
    }
}

void
dconf_reader_list (DConfReader *reader,
                   const gchar *path,
                   GTree       *tree,
                   gboolean    *locked)
{
  const volatile struct dir_entry *entries;
  gint n_entries;
  guint32 index;
  gint i;

  if (!dconf_reader_ensure_valid (reader))
    return;

  index = reader->data.super->root_index;

  if (path[0] != '\0')
    {
      const volatile struct dir_entry *entry;

      entry = dconf_reader_get_entry (reader, path, index, locked);

      if (entry == NULL)
        return;

      index = entry->data.index;
    }

  entries = dconf_reader_get_dir (reader, index, &n_entries);

  if (entries == NULL)
    return;

  for (i = 0; i < n_entries; i++)
    {
      const volatile gchar *name;
      guint32 namelen;

      name = dconf_reader_get_entry_name (reader, &entries[i], &namelen);

      if (name != NULL)
        {
          gchar *my_name;

          my_name = g_strndup ((const gchar *) name, namelen);

          if (g_tree_lookup (tree, my_name) == NULL)
            g_tree_insert (tree, my_name, my_name);
          else
            g_free (my_name);
        }
    }
}

gboolean
dconf_reader_get_writable (DConfReader *reader,
                           const gchar *name)
{
  const volatile struct dir_entry *entry;
  gboolean locked = FALSE;

  if (!dconf_reader_ensure_valid (reader))
    return FALSE;

  if (name[0] != '\0')
    entry = dconf_reader_get_entry (reader, name,
                                    reader->data.super->root_index,
                                    &locked);

  return !locked;
}

gboolean
dconf_reader_get_locked (DConfReader *reader,
                         const gchar *name)
{
  const volatile struct dir_entry *entry;
  gboolean locked = FALSE;

  if (!dconf_reader_ensure_valid (reader))
    return FALSE;

  if (name[0] == '\0')
    return FALSE;

  entry = dconf_reader_get_entry (reader, name,
                                  reader->data.super->root_index,
                                  &locked);

  if (entry == NULL)
    return FALSE;

  return entry->locked;
}
