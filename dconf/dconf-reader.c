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

#include <glib.h>

#include "dconf-format.h"

struct OPAQUE_TYPE__DConfReader
{
  GMappedFile *mapped_file;
  gchar *filename;

  union
  {
    const volatile struct superblock *super;
    const volatile struct chunk_header *blocks;
  } data;

  const volatile void *end;
};

typedef const volatile struct dir_entry de;

DConfReader *
dconf_reader_new (const gchar *filename)
{
  DConfReader *reader;

  g_assert (sizeof (struct superblock) == 32);
  g_assert (sizeof (struct dir_entry) == 48);
  g_assert (sizeof (struct chunk_header) == 8);

  reader = g_slice_new0 (DConfReader);
  reader->filename = g_strdup (filename);

  return reader;
}

static gboolean
dconf_reader_ensure_valid (DConfReader *reader)
{
  if (reader->data.super &&
      (reader->data.super->flags & DCONF_FLAG_STALE))
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

      if (size < sizeof (struct superblock))
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
dconf_reader_range_ok (DConfReader         *reader,
                       const volatile void *start,
                       const volatile void *end)
{
  return (const volatile void *) reader->data.blocks <= start &&
         start <= end &&
         end <= reader->end;
}

#define dconf_reader_index_ok(reader, array, index) \
  (dconf_reader_range_ok (reader, &array[index], &array[index + 1]))

static const volatile void *
dconf_reader_get_chunk (DConfReader *reader,
                        guint32      index,
                        guint32     *size)
{
  const volatile struct chunk_header *header;

  *size = 0;

  if (index < 4)
    return NULL;

  if (!dconf_reader_index_ok (reader, reader->data.blocks, index))
    return NULL;

  header = &reader->data.blocks[index];

  if (!dconf_reader_range_ok (reader, header->contents,
                              header->contents + header->size))
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

  entries = dconf_reader_get_chunk (reader, index, &size);

  if (size % sizeof (struct dir_entry))
    {
      entries = NULL;
      size = 0;
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

  if (*name_length == 0 || *name_length > sizeof entry->name.direct)
    return dconf_reader_get_chunk (reader, entry->name.index, name_length);

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

      if (entry->type &&
          entry_namelen == name_length &&
          memcmp ((gchar *) entry_name, name, name_length) == 0)
        return entry;
    }

  return NULL;
}

static const volatile struct dir_entry *
dconf_reader_find_next (DConfReader                      *reader,
                        const volatile struct dir_entry  *entries,
                        gint                              n_entries,
                        const gchar                      *name,
                        const gchar                     **next_name)
{
  const gchar *next;

  for (next= name; *next; next++)
    if (*next== '/')
      {
        next++;
        break;
      }

  if (next_name)
    *next_name = next;

  return dconf_reader_find_entry (reader,
                                  entries, n_entries,
                                  name, next - name);
}

static const volatile struct dir_entry *
dconf_reader_get_entry (DConfReader *reader,
                        const gchar *name,
                        guint32      starting_index,
                        gboolean    *locked)
{
  const volatile struct dir_entry *entries;
  const volatile struct dir_entry *entry;
  const gchar *next;
  gint n_entries;

  entries = dconf_reader_get_dir (reader, starting_index, &n_entries);
  entry = dconf_reader_find_next (reader, entries, n_entries, name, &next);

  if (entry != NULL)
    {
      if (locked && entry->locked)
        *locked = TRUE;

      if (*next)
        return dconf_reader_get_entry (reader, next,
                                       entry->data.index,
                                       locked);
    }

  return entry;
}

void
dconf_reader_get (DConfReader  *reader,
                  const gchar  *key,
                  GVariant    **value,
                  gboolean     *locked)
{
  const volatile struct dir_entry *entry;
  char type;

  if (!dconf_reader_ensure_valid (reader))
    return;

  if (reader->data.super->flags & DCONF_FLAG_LOCKED)
    *locked = TRUE;

  entry = dconf_reader_get_entry (reader, key,
                                  reader->data.super->root_index,
                                  locked);

  if (!entry || !(type = entry->type))
    return;

  if (*value)
    g_variant_unref (*value);

  switch (type)
    {
     case G_VARIANT_TYPE_CLASS_BOOLEAN:
      *value = g_variant_new_boolean (entry->data.byte);
      g_variant_ref_sink (*value);
      break;

     case G_VARIANT_TYPE_CLASS_BYTE:
      *value = g_variant_new_byte (entry->data.byte);
      g_variant_ref_sink (*value);
      break;

     case G_VARIANT_TYPE_CLASS_INT16:
      *value = g_variant_new_int16 (entry->data.uint16);
      g_variant_ref_sink (*value);
      break;

     case G_VARIANT_TYPE_CLASS_UINT16:
      *value = g_variant_new_uint16 (entry->data.uint16);
      g_variant_ref_sink (*value);
      break;

     case G_VARIANT_TYPE_CLASS_INT32:
      *value = g_variant_new_int32 (entry->data.uint32);
      g_variant_ref_sink (*value);
      break;

     case G_VARIANT_TYPE_CLASS_UINT32:
      *value = g_variant_new_uint32 (entry->data.uint32);
      g_variant_ref_sink (*value);
      break;

     case G_VARIANT_TYPE_CLASS_INT64:
      *value = g_variant_new_int64 (entry->data.uint64);
      g_variant_ref_sink (*value);
      break;

     case G_VARIANT_TYPE_CLASS_UINT64:
      *value = g_variant_new_uint64 (entry->data.uint64);
      g_variant_ref_sink (*value);
      break;

     case G_VARIANT_TYPE_CLASS_DOUBLE:
      *value = g_variant_new_double (entry->data.floating);
      g_variant_ref_sink (*value);
      break;

     default:
      {
        const volatile void *data;
        guint32 size;

        data = dconf_reader_get_chunk (reader, entry->data.index, &size);

        g_mapped_file_ref (reader->mapped_file);
        *value = g_variant_from_data (NULL, (gconstpointer) data, size, 0,
                                      (GDestroyNotify) g_mapped_file_unref,
                                      reader->mapped_file);

        break;
      }
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

  if (*path) /* ie: not the root directory */
    {
      const volatile struct dir_entry *entry;

      entry = dconf_reader_get_entry (reader, path, index, locked);

      if (entry == NULL)
        return;

      index = entry->data.index;
    }

  entries = dconf_reader_get_dir (reader, index, &n_entries);

  for (i = 0; i < n_entries; i++)
    if (entries[i].type != '\0')
      {
        const volatile gchar *name;
        guint32 namelen;

        name = dconf_reader_get_entry_name (reader, &entries[i], &namelen);
        g_tree_insert (tree, g_strndup ((const gchar *) name, namelen), 0);
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

  if (reader->data.super->flags & DCONF_FLAG_LOCKED)
    locked = TRUE;

  if (*name)
    entry = dconf_reader_get_entry (reader, name,
                                    reader->data.super->root_index,
                                    &locked);

  return !locked;
}

gboolean
dconf_reader_get_locked (DConfReader *reader,
                         const gchar *name)
{
  if (!dconf_reader_ensure_valid (reader))
    return FALSE;

  if (*name)
    {
      const volatile struct dir_entry *entry;

      if ((entry = dconf_reader_get_entry (reader, name,
                                           reader->data.super->root_index,
                                           NULL)) == NULL)
        return FALSE;

      return entry->locked;
    }

  else
    return (reader->data.super->flags & DCONF_FLAG_LOCKED) != 0;
}
