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
                          guint32      *index,
                          const gchar  *name,
                          GError      **error)
{
  volatile struct dir_entry *entries;
  volatile struct dir_entry *entry;
  const gchar *next;
  gint n_entries;
  gint i;

  entries = dconf_writer_get_dir (writer, *index, &n_entries);
  entry = dconf_writer_next_entry (writer, entries, n_entries, name, &next);

  if (entry == NULL || entry->type == '\0')
    {
      g_set_error (error, 0, 0, "no such entry");
      return FALSE;
    }

  for (i = 0; i < n_entries; i++)
    if (&entries[i] != entry && entries[i].type != '\0')
      break;

  if (*next)
    {
      guint32 subindex = entry->data.index;

      if (!dconf_writer_unset_index (writer, &subindex, next, error))
        return FALSE;

      if (subindex)
        return TRUE;
    }

  if (i < n_entries)
    entry->type = '\0';
  else
    *index = 0;

  return TRUE;
}

gboolean
dconf_writer_unset (DConfWriter  *writer,
                    const gchar  *key,
                    GError      **error)
{
  volatile struct superblock *super = writer->data.super;
  guint32 index;

  index = dconf_writer_get_index (writer, &super->root_index, FALSE);
  if (!dconf_writer_unset_index (writer, &index, key, error))
    return FALSE;
  dconf_writer_set_index (writer, &super->root_index, index, TRUE);

  return TRUE;
}
