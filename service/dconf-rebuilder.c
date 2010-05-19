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

#include "gvdb-reader.h"
#include "gvdb-builder.h"

typedef struct
{
  const gchar *prefix;
  gint prefix_len;

  GHashTable *table;
  const gchar **keys;
  GVariant **values;
  gint n_items;
  gint index;

  gchar name[4096];
  gint name_len;
} DConfRebuilderState;

static GvdbItem *
dconf_rebuilder_get_parent (GHashTable *table,
                            gchar      *key,
                            gint        length)
{
  GvdbItem *grandparent, *parent;

  if (length == 1)
    return NULL;

  while (key[--length - 1] != '/');
  key[length] = '\0';

  parent = g_hash_table_lookup (table, key);

  if (parent == NULL)
    {
      parent = gvdb_hash_table_insert (table, key);

      grandparent = dconf_rebuilder_get_parent (table, key, length);

      if (grandparent != NULL)
        gvdb_item_set_parent (parent, grandparent);
    }

  return parent;
}

static void
dconf_rebuilder_insert (GHashTable  *table,
                        const gchar *key,
                        GVariant    *value)
{
  GvdbItem *item;
  gchar *mykey;
  gint length;

  length = strlen (key);
  mykey = g_alloca (length);
  memcpy (mykey, key, length);

  g_assert (g_hash_table_lookup (table, key) == NULL);
  item = gvdb_hash_table_insert (table, key);

  gvdb_item_set_parent (item,
                        dconf_rebuilder_get_parent (table, mykey, length));

  gvdb_item_set_value (item, value);
}

static void
dconf_rebuilder_put_item (DConfRebuilderState *state)
{
  if (state->values[state->index] != NULL)
    {
      gchar *fullname;
      GVariant *ouch;

      fullname = g_strconcat (state->prefix, state->keys[state->index], NULL);
      ouch = g_variant_get_variant (state->values[state->index]);
      dconf_rebuilder_insert (state->table, fullname, ouch);
      g_variant_unref (ouch);
      g_free (fullname);
    }

  state->index++;
}

static gboolean
dconf_rebuilder_walk_name (DConfRebuilderState *state,
                           const gchar         *name,
                           gsize                name_len)
{
  gint cmp;

  g_assert (state->name_len + name_len < sizeof state->name - 1);
  memcpy (state->name + state->name_len, name, name_len);
  state->name[state->name_len + name_len] = '\0';

  if (state->index == state->n_items)
    return TRUE;

  if (state->name_len + name_len < state->prefix_len ||
      memcmp (state->name, state->prefix, state->prefix_len) != 0)
    return TRUE;

  while ((cmp = strcmp (state->name + state->prefix_len,
                        state->keys[state->index])) > 0)
    {
      dconf_rebuilder_put_item (state);

      if (state->index == state->n_items)
        return TRUE;
    }

  return cmp != 0;
}

static void
dconf_rebuilder_walk_value (const gchar *name,
                            gsize        name_len,
                            GVariant    *value,
                            gpointer     user_data)
{
  DConfRebuilderState *state = user_data;

  if (dconf_rebuilder_walk_name (state, name, name_len))
    dconf_rebuilder_insert (state->table, state->name, value);

  else
    dconf_rebuilder_put_item (state);
}

static gboolean
dconf_rebuilder_walk_open (const gchar *name,
                           gsize        name_len,
                           gpointer     user_data)
{
  DConfRebuilderState *state = user_data;

  if (dconf_rebuilder_walk_name (state, name, name_len))
    {
      state->name_len += name_len;
      return TRUE;
    }

  return FALSE;
}

static void
dconf_rebuilder_walk_close (gpointer user_data)
{
  DConfRebuilderState *state = user_data;

  while (--state->name_len && state->name[state->name_len - 1] != '/');
}

gboolean
dconf_rebuilder_rebuild (const gchar  *filename,
                         const gchar  *prefix,
                         const gchar **keys,
                         GVariant    **values,
                         int           n_items,
                         GError      **error)
{
  DConfRebuilderState state = { prefix, strlen (prefix),
                                0, keys, values, n_items };
  GvdbTable *old;

  state.table = gvdb_hash_table_new (NULL, NULL);

  if ((old = gvdb_table_new (filename, FALSE, NULL)))
    gvdb_table_walk (old, "/",
                     dconf_rebuilder_walk_open,
                     dconf_rebuilder_walk_value,
                     dconf_rebuilder_walk_close,
                     &state);

  while (state.index != state.n_items)
    dconf_rebuilder_put_item (&state);

  return gvdb_table_write_contents (state.table, filename, FALSE, error);
}
