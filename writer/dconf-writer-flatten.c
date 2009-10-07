/*
 * Copyright © 2007, 2008  Ryan Lortie
 * Copyright © 2009 Codethink Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 2.1
 * of the licence, or (at your option) any later version.
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
  guint32 root_index;
  GTree *tree;

  tree = g_tree_new_full ((GCompareDataFunc) strcmp, NULL,
                          g_free, (GDestroyNotify) g_variant_unref);

  root_index = dconf_writer_get_index (writer,
                                       &writer->data.super->root_index,
                                       TRUE);

  dconf_writer_flatten_index (writer, tree, "", 0, root_index);

  return tree;
}

static gboolean
dconf_writer_dump_entry (gpointer key,
                         gpointer value,
                         gpointer user_data)
{
  gchar *string;

  string = g_variant_print (value, TRUE);
  g_message ("  %s = %s", (const gchar *) key, string);
  g_free (string);

  return FALSE;
}

struct measure_tree_state
{
  const gchar *last;
  gint blocks;
};

static gboolean
dconf_writer_measure_entry (gpointer key,
                            gpointer value,
                            gpointer user_data)
{
  struct measure_tree_state *mts = user_data;
  const gchar *this = key;
  gint part = 0;
  gint i;

  /* find the common part of the path */
  if (mts->last)
    for (i = 0; mts->last[i] == this[i]; i++);
  else
    i = 0;

  /* for each new directory component (ie: ending in '/'):
   *    - we need a chunk header for that directory (1 block)
   *    - we need a directory entry to point at that chunk (6 blocks)
   *    - if the name is long, we need to store it separately
   */
  while (this[i])
    {
      if (this[i++] == '/')
        {
          mts->blocks += sizeof (struct chunk_header) / 8;
          mts->blocks += sizeof (struct dir_entry) / 8;

          if (i - part > 36)
            {
              /* long filename */
              mts->blocks += sizeof (struct chunk_header) / 8;
              mts->blocks += (i - part + 7) / 8;
            }

          part = i;
        }
    }

  /* for each value:
   *    - we need a chunk to store the value if it is non-atomic
   *    - we need a directory entry in any case (6 blocks)
   *    - if the name is long, we need to store it separately
   */
  if (! (/*atomic*/0))
    {
      GVariant *variant;

      variant = g_variant_ref_sink (g_variant_new_variant (value));
      mts->blocks += sizeof (struct chunk_header) / 8;
      mts->blocks += (g_variant_get_size (variant) + 7) / 8;
      g_variant_unref (variant);
    }

  mts->blocks += sizeof (struct dir_entry) / 8;

  if (i - part > 36)
    {
      /* long filename */
      mts->blocks += sizeof (struct chunk_header) / 8;
      mts->blocks += (i - part + 7) / 8;
    }

  /* next entry probably shares a lot in common with this one so save
   * our path so that we can determine the amount of overlap.
   */
  mts->last = this;

  return FALSE;
}

gint
dconf_writer_measure_tree (GTree *tree)
{
  struct measure_tree_state state;

  state.last = NULL;
  state.blocks = sizeof (struct superblock) / 8;
  state.blocks += sizeof (struct chunk_header) / 8;

  g_tree_foreach (tree, dconf_writer_measure_entry, &state);

  return state.blocks;
}

void
dconf_writer_dump (DConfWriter *writer)
{
  GTree *tree;


  tree = dconf_writer_flatten (writer);
  g_message ("dumping contents of dconf database");
  g_tree_foreach (tree, dconf_writer_dump_entry, NULL);
  g_message ("end of output");

  g_message ("tree has %d blocks", dconf_writer_measure_tree (tree));

  g_tree_unref (tree);
}

static gboolean
dconf_writer_unzip_entry (gpointer key,
                          gpointer value,
                          gpointer user_data)
{
  gpointer *(*args)[2] = user_data;

  *((*args)[0]++) = key;
  *((*args)[1]++) = value;

  return FALSE;
}

void
dconf_writer_unzip_tree (GTree         *tree,
                         const gchar ***names,
                         GVariant    ***values,
                         gint          *num)
{
  gpointer args[2];

  *num = g_tree_nnodes (tree);
  *names = g_new (const gchar *, *num);
  *values = g_new (GVariant *, *num);

  args[0] = *names;
  args[1] = *values;
  g_tree_foreach (tree, dconf_writer_unzip_entry, args);
}
