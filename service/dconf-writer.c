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

#include "dconf-writer.h"

#include "dconf-rebuilder.h"
#include "dconf-state.h"
#include "../shm/dconf-shm.h"

#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>

struct OPAQUE_TYPE__DConfWriter
{
  DConfState *state;
  gchar *name;
  gchar *path;
};

/* Each element must only contain the ASCII characters "[A-Z][a-z][0-9]_"
 */
static gboolean
is_valid_dbus_path_element (const gchar *string)
{
  gint i;

  for (i = 0; string[i]; i++)
    if (!g_ascii_isalnum (string[i]) && string[i] != '_')
      return FALSE;

  return TRUE;
}

gchar **
dconf_writer_list_existing (void)
{
  GPtrArray *array;
  gchar *path;
  GDir *dir;

  path = g_build_filename (g_get_user_config_dir (), "dconf", NULL);
  array = g_ptr_array_new ();

  if ((dir = g_dir_open (path, 0, NULL)))
    {
      const gchar *name;

      while ((name = g_dir_read_name (dir)))
        if (is_valid_dbus_path_element (name))
          g_ptr_array_add (array, g_strdup (name));
    }

  g_ptr_array_add (array, NULL);
  g_free (path);

  return (gchar **) g_ptr_array_free (array, FALSE);
}

gboolean
dconf_writer_write (DConfWriter  *writer,
                    const gchar  *name,
                    GVariant     *value,
                    GError      **error)
{
  if (!dconf_rebuilder_rebuild (writer->path, "", &name, &value, 1, error))
    return FALSE;

  dconf_shm_flag (writer->name);

  return TRUE;
}

gboolean
dconf_writer_write_many (DConfWriter          *writer,
                         const gchar          *prefix,
                         const gchar * const  *keys,
                         GVariant * const     *values,
                         gsize                 n_items,
                         GError              **error)
{
  if (!dconf_rebuilder_rebuild (writer->path, prefix, keys,
                                values, n_items, error))
    return FALSE;

  dconf_shm_flag (writer->name);

  return TRUE;
}

gboolean
dconf_writer_change (DConfWriter     *writer,
                     DConfChangeset  *change,
                     GError         **error)
{
  const gchar * const *keys;
  GVariant * const *values;
  const gchar *prefix;
  gint n_items;

  n_items = dconf_changeset_describe (change, &prefix, &keys, &values);

  if (!n_items)
    return TRUE;

  if (!dconf_rebuilder_rebuild (writer->path, prefix, keys, values, n_items, error))
    return FALSE;

  dconf_shm_flag (writer->name);

  return TRUE;
}

const gchar *
dconf_writer_get_name (DConfWriter *writer)
{
  return writer->name;
}

DConfState *
dconf_writer_get_state (DConfWriter *writer)
{
  return writer->state;
}

DConfWriter *
dconf_writer_new (DConfState  *state,
                  const gchar *name)
{
  DConfWriter *writer;

  writer = g_slice_new (DConfWriter);
  writer->state = state;
  writer->path = g_build_filename (state->db_dir, name, NULL);
  writer->name = g_strdup (name);

  return writer;
}
