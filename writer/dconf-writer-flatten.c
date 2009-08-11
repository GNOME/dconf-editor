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

#include <string.h>

static gboolean
dconf_writer_check_name (const gchar *name,
                         guint32      namelen,
                         gboolean    *is_directory)
{
  gint i;

  if (namelen == 0)
    return FALSE;

  if (namelen == 1 && name[0] == '/')
    return FALSE;

  for (i = 0; i < namelen - 1; i++)
    if (name[i] == '/')
      return FALSE;

  *is_directory = name[i] == '/';

  return TRUE;
}

static void
dconf_writer_flatten_index (DConfWriter *writer,
                            GTree       *tree,
                            const gchar *prefix,
                            gint         prefixlen,
                            guint32      index)
{
  const volatile struct dir_entry *entries;
  gint n_items;
  gint i;

  entries = dconf_writer_get_dir (writer, index, &n_items);

  for (i = 0; i < n_items; i++)
    {
      const volatile struct dir_entry *entry = &entries[i];
      gboolean is_directory;
      const gchar *name;
      guint32 namelen;
      gint pathlen;
      gchar *path;

      name = dconf_writer_get_entry_name (writer, entry, &namelen);

      if (!dconf_writer_check_name (name, namelen, &is_directory))
        continue;

      pathlen = prefixlen + namelen;
      path = g_malloc (pathlen + 1);
      memcpy (path, prefix, prefixlen);
      memcpy (path + prefixlen, name, namelen);
      path[pathlen] = '\0';

      if (is_directory)
        {
          index = dconf_writer_get_index (writer, &entry->data.index, TRUE);
          dconf_writer_flatten_index (writer, tree, path, pathlen, index);
          g_free (path);
        }
      else
        {
          g_tree_insert (tree, path,
                         dconf_writer_get_entry_value (writer, entry));
        }
    }
}

GTree *
dconf_writer_flatten (DConfWriter *writer)
{
  GTree *tree;

  tree = g_tree_new_full ((GCompareDataFunc) strcmp, NULL,
                          g_free, (GDestroyNotify) g_variant_unref);

  dconf_writer_flatten_index (writer, tree, "", 0,
                              writer->data.super->root_index);

  return tree;
}

static gboolean
dconf_writer_dump_entry (gpointer key,
                         gpointer value,
                         gpointer user_data)
{
  GString *string;

  string = g_variant_markup_print (value, NULL, 0, 0, 0);
  g_message ("  %s = %s", (const gchar *) key, string->str);
  g_string_free (string, TRUE);

  return FALSE;
}

void
dconf_writer_dump (DConfWriter *writer)
{
  GTree *tree;

  tree = dconf_writer_flatten (writer);
  g_message ("dumping contents of dconf database");
  g_tree_foreach (tree, dconf_writer_dump_entry, NULL);
  g_message ("end of output");
  g_tree_unref (tree);
}
