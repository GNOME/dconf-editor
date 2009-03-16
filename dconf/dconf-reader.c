/*
 * Copyright © 2007, 2008 Ryan Lortie
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
  gpointer data;
  gsize size;
  gint ref_count;
};

static DConfReader *
dconf_reader_new (const gchar *filename)
{
  DConfReader *reader;
  gpointer pointer;
  struct stat buf;
  gint fd;

  if (filename[0] == '.')
    switch (filename[1])
      {
        case 'd':
          fd = open ("/etc/dconf/default.db", O_RDONLY);
          break;

        case 'u':
          {
            gchar *f = g_strdup_printf ("%s/dconf.db",
                g_get_user_config_dir ());
            fd = open (f, O_RDONLY);
            g_free (f);
            break;
          }

        case 's':
          fd = open ("/etc/dconf/system.db", O_RDONLY);
          break;

        default:
          g_assert_not_reached ();
      }
  else
    fd = open (filename, O_RDONLY);

  if (fd < 0)
    return NULL;

  if (fstat (fd, &buf))
    {
      close (fd);
      return NULL;
    }

  pointer = mmap (NULL, buf.st_size, PROT_READ, MAP_SHARED, fd, 0);
  close (fd);

  if (pointer == MAP_FAILED)
    return NULL;
    
  reader = g_slice_new (DConfReader);
  reader->data = pointer;
  reader->size = buf.st_size;
  reader->ref_count = 1;

  return reader;
}

DConfReader *
dconf_reader_ref (DConfReader *reader)
{
  g_atomic_int_inc (&reader->ref_count);

  return reader;
}

void
dconf_reader_unref (DConfReader *reader)
{
  if (g_atomic_int_dec_and_test (&reader->ref_count))
    {
      munmap (reader->data, reader->size);
      g_slice_free (DConfReader, reader);
    }
}

static DConfReader *
dconf_reader_ensure_valid (const gchar  *filename,
                           DConfReader **reader_ptr)
{
  if (*reader_ptr == NULL)
    *reader_ptr = dconf_reader_new (filename);

  else if (((struct superblock *) (*reader_ptr)->data)->invalid)
    {
      /* XXX this is not threadsafe, k? */
      dconf_reader_unref (*reader_ptr);
      *reader_ptr = dconf_reader_new (filename);
    }

  return *reader_ptr;
}

static const volatile struct dir_entry *
binary_search (const volatile struct dir_entry *entries,
               gint                             n_entries,
               const gchar                     *name,
               gint                             name_len)
{
  const gchar *ename;
  gint guess, cmp;

  if (n_entries == 0)
    return NULL;

  guess = n_entries / 2;

  ename = (const/*volatile*/gchar *) entries[guess].name.direct;
  if (!(cmp = memcmp (name, ename, MIN (name_len, entries[guess].namelen))))
    cmp = name_len - entries[guess].namelen;

  if (cmp < 0)
    return binary_search (entries, guess, name, name_len);

  else if (cmp > 0)
    return binary_search (entries + guess + 1, n_entries - guess - 1, name, name_len);

  return &entries[guess];
}

static gpointer
dconf_reader_deref_index (DConfReader *reader,
                          guint32      index,
                          gsize       *size)
{
  struct block_header *headers = reader->data;

  /* XXX some checks would make sense here */
  *size = headers[index].size;
  return &headers[index + 1];
}

static guint32
dconf_reader_get_root_index (DConfReader *reader)
{
  const volatile struct superblock *super;

  super = reader->data;

  return super->root_index;
}

/* corecursion */
static const volatile struct dir_entry *
dconf_reader_get_entry (DConfReader *reader,
                        const gchar *path_or_key,
                        gint         path_or_key_length,
                        gboolean    *locked);

static const volatile struct dir_entry *
dconf_reader_get_directory (DConfReader *reader,
                            const gchar *path,
                            gint         path_length,
                            gint        *length,
                            gboolean    *locked)
{
  const volatile struct dir_entry *my_entries;
  guint32 block_index;
  guint32 size;

  if (path_length > 1)
    {
      const volatile struct dir_entry *entry_in_parent;

      entry_in_parent = dconf_reader_get_entry (reader, path,
                                                path_length, locked);

      if (entry_in_parent == NULL)
        return NULL;

      block_index = entry_in_parent->data.index;
    }
  else
    block_index = dconf_reader_get_root_index (reader);

  my_entries = dconf_reader_deref_index (reader, block_index, &size);

  if (size % sizeof (struct dir_entry) || my_entries == NULL)
    {
      g_warning ("corrupt dconf db");
      return NULL;
    }

  *length = size / sizeof (struct dir_entry);

  return my_entries;
}

static const volatile struct dir_entry *
dconf_reader_get_entry (DConfReader *reader,
                        const gchar *path_or_key,
                        gint         path_or_key_length,
                        gboolean    *locked)
{
  const volatile struct dir_entry *entries;
  const volatile struct dir_entry *entry;
  const gchar *basename;
  gint basename_length;
  gint pathname_length;
  gint n_entries;

  pathname_length = path_or_key_length - 1;

  while (pathname_length &&
         path_or_key[pathname_length - 1] != '/')
    pathname_length--;

  basename_length = path_or_key_length - pathname_length;
  basename = path_or_key + pathname_length;

  entries = dconf_reader_get_directory (reader, path_or_key,
                                        pathname_length, &n_entries,
                                        locked);

  if (entries == NULL)
    return NULL;

  entry = binary_search (entries, n_entries, basename, basename_length);

  if (entry)
    *locked |= entry->locked;

  return entry;
}

void
dconf_reader_get (const gchar  *filename,
                  DConfReader **reader,
                  const gchar  *key,
                  GVariant    **value,
                  gboolean     *locked)
{
  const volatile struct dir_entry *entry;
  char type;

  if (!dconf_reader_ensure_valid (filename, reader))
    return;

  entry = dconf_reader_get_entry (*reader, key, strlen (key), locked);

  if (entry == NULL)
    return;

  if (locked != NULL && entry->locked)
    *locked = TRUE;

  type = entry->type;

  if (*value)
    g_variant_unref (*value);

  if (type == 'v')
    {
      gpointer data;
      gsize size;

      data = dconf_reader_deref_index (*reader, entry->data.index, &size);
      *value = g_variant_load (NULL, data, size, 0);
    }

  else if (type == 'v')
    {
      gpointer data;
      gsize size;

      data = dconf_reader_deref_index (*reader, entry->data.index, &size);
      *value = g_variant_load (NULL, data, size, 0);
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
dconf_reader_list (const gchar  *filename,
                   DConfReader **reader,
                   const gchar  *path,
                   GTree        *tree,
                   gboolean     *locked)
{
  const volatile struct dir_entry *entries;
  gint n_entries, i;

  if (!dconf_reader_ensure_valid (filename, reader))
    return;

  entries = dconf_reader_get_directory (*reader,
                                        path, strlen (path),
                                        &n_entries, locked);

  if (entries == NULL)
    return;

  for (i = 0; i < n_entries; i++)
    {
      const gchar *name;
      gchar *my_name;

      name = (const/*volatile*/gchar *) entries[i].name.direct;
      my_name = g_strndup (name, entries[i].namelen);
      if (g_tree_lookup (tree, my_name) == NULL)
        g_tree_insert (tree, my_name, my_name);
      else
        g_free (my_name);
    }
}
