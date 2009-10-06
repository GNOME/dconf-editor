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

static volatile struct dir_entry *
dconf_writer_get_entry (DConfWriter *writer,
                        const gchar *name,
                        guint32      starting_index)
{
  volatile struct dir_entry *entries;
  volatile struct dir_entry *entry;
  const gchar *next;
  gint n_entries;

  entries = dconf_writer_get_dir (writer, starting_index, &n_entries);

  if (entries == NULL)
    return NULL;

  entry = dconf_writer_next_entry (writer, entries, n_entries, name, &next);

  if (entry == NULL)
    return NULL;

  if (*next == '\0')
    return entry;

  return dconf_writer_get_entry (writer, next, entry->data.index);
}

static volatile struct dir_entry *
dconf_writer_lookup (DConfWriter *writer,
                     const gchar *name)
{
  return dconf_writer_get_entry (writer, name,
                                 writer->data.super->root_index);
}

gboolean
dconf_writer_set_locked (DConfWriter  *writer,
                         const gchar  *name,
                         gboolean      locked,
                         GError      **error)
{
  volatile struct dir_entry *entry;

  g_assert (name[0] == '/');
  name++;

  if ((entry = dconf_writer_lookup (writer, name)) == NULL)
    {
      g_set_error (error, 0, 0, "Unable to lock non-existent entry.");
      return FALSE;
    }

  entry->locked = locked;

  return TRUE;
}

gboolean
dconf_writer_check_set_locked (const gchar  *name,
                               GError      **error)
{
  gint i;

  if (name[0] != '/')
    {
      g_set_error (error, 0, 0,
                   "name must start with a slash");
      return FALSE;
    }

  for (i = 1; name[i]; i++)
    if (name[i] == '/' && name[i - 1] == '/')
      {
        g_set_error (error, 0, 0,
                     "name must not contain two adjacent slashes");
        return FALSE;
      }

  return TRUE;
}
