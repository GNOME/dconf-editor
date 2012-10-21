/*
 * Copyright © 2010 Codethink Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the licence, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "dconf-rebuilder.h"

#include <string.h>

#include "../gvdb/gvdb-reader.h"
#include "../gvdb/gvdb-builder.h"
#include "../common/dconf-paths.h"

static GvdbItem *
dconf_rebuilder_get_parent (GHashTable  *table,
                            const gchar *key)
{
  GvdbItem *grandparent, *parent;
  gchar *parent_name;
  gint len;

  if (g_str_equal (key, "/"))
    return NULL;

  len = strlen (key);
  if (key[len - 1] == '/')
    len--;

  while (key[len - 1] != '/')
    len--;

  parent_name = g_strndup (key, len);
  parent = g_hash_table_lookup (table, parent_name);

  if (parent == NULL)
    {
      parent = gvdb_hash_table_insert (table, parent_name);

      grandparent = dconf_rebuilder_get_parent (table, parent_name);

      if (grandparent != NULL)
        gvdb_item_set_parent (parent, grandparent);
    }
  g_free (parent_name);

  return parent;
}

gboolean
dconf_rebuilder_rebuild (const gchar          *filename,
                         const gchar          *prefix,
                         const gchar * const  *keys,
                         GVariant * const     *values,
                         int                   n_items,
                         GError              **error)
{
  GHashTable *table;
  gboolean success;
  GHashTable *new;
  GvdbTable *old;
  gint i;

  table = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, (GDestroyNotify) g_variant_unref);

  /* read in the old values */
  if ((old = gvdb_table_new (filename, FALSE, NULL)))
    {
      gchar **names;
      gint n_names;
      gint i;

      names = gvdb_table_get_names (old, &n_names);
      for (i = 0; i < n_names; i++)
        {
          if (dconf_is_key (names[i], NULL))
            {
              GVariant *value;

              value = gvdb_table_get_value (old, names[i]);

              if (value != NULL)
                {
                  g_hash_table_insert (table, names[i], value);
                  names[i] = NULL;
                }
            }

          g_free (names[i]);
        }

      gvdb_table_unref (old);
      g_free (names);
    }

  /* apply the requested changes */
  for (i = 0; i < n_items; i++)
    {
      gchar *path = g_strconcat (prefix, keys[i], NULL);

      /* Check if we are performing a path reset */
      if (g_str_has_suffix (path, "/"))
        {
          GHashTableIter iter;
          gpointer key;

          g_assert (values[i] == NULL);

          /* A path reset is really a request to delete all keys that
           * has a name starting with the reset path.
           */
          g_hash_table_iter_init (&iter, table);
          while (g_hash_table_iter_next (&iter, &key, NULL))
            if (g_str_has_prefix (key, path))
              g_hash_table_iter_remove (&iter);
        }

      if (values[i] != NULL)
        g_hash_table_insert (table, g_strdup (path), g_variant_ref (values[i]));
      else
        g_hash_table_remove (table, path);

      g_free (path);
    }

  /* convert back to GVDB format */
  {
    GHashTableIter iter;
    gpointer key, value;

    new = gvdb_hash_table_new (NULL, NULL);

    g_hash_table_iter_init (&iter, table);
    while (g_hash_table_iter_next (&iter, &key, &value))
      {
        GvdbItem *item;

        g_assert (g_hash_table_lookup (new, key) == NULL);
        item = gvdb_hash_table_insert (new, key);
        gvdb_item_set_parent (item, dconf_rebuilder_get_parent (new, key));
        gvdb_item_set_value (item, value);
      }
  }

  /* write the new file */
  success = gvdb_table_write_contents (new, filename, FALSE, error);

  /* clean up */
  g_hash_table_unref (table);
  g_hash_table_unref (new);

  return success;
}
