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

#include <glib.h>

static gboolean
dconf_writer_unset_index (DConfWriter  *writer,
                          guint32       index,
                          const gchar  *name,
                          gboolean     *delete_entire_dir,
                          GError      **error)
{
  volatile struct dir_entry *entries;
  volatile struct dir_entry *entry;
  gboolean other_content = FALSE;
  const gchar *next;
  gint n_entries;
  gint i;

  if ((entries = dconf_writer_get_dir (writer, index, &n_entries)) == NULL)
    {
      *delete_entire_dir = TRUE;
      return TRUE;
    }

  entry = dconf_writer_next_entry (writer, entries, n_entries, name, &next);

  if (entry == NULL)
    {
      g_set_error (error, 0, 0, "no such entry");
      return FALSE;
    }

  for (i = 0; i < n_entries; i++)
    {
      if (&entries[i] == entry)
        continue;

      if (dconf_writer_entry_is_valid (writer, &entries[i]))
        {
          other_content = TRUE;
          break;
        }
    }

  if (other_content == FALSE)
    {
      if (*next)
        return dconf_writer_unset_index (writer, entry->data.index,
                                         next, delete_entire_dir, error);

      else
        *delete_entire_dir = TRUE;
    }

  else
    {
      if (*next)
        {
          gboolean delete_this_dir;

          if (!dconf_writer_unset_index (writer, entry->data.index,
                                         next, &delete_this_dir, error))
            return FALSE;

          if (delete_this_dir)
            entry->data.index = 0;
        }

      else
        {
          if (entry->type == 'v')
            entry->data.index = 0;

          else
            entry->type = '\0';
        }

      *delete_entire_dir = FALSE;
    }

  return TRUE;
}

gboolean
dconf_writer_unset (DConfWriter  *writer,
                    const gchar  *key,
                    GError      **error)
{
  gboolean delete_all;

  if (!dconf_writer_unset_index (writer,
                                 writer->super->root_index,
                                 key, &delete_all, error))
    return FALSE;

  if (delete_all)
    writer->super->root_index = 0;

  return TRUE;
}
