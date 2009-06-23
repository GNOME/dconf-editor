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

#include "dconf-config.h"

#include <string.h>
#include <stdio.h>

typedef struct
{
  gchar *name;
  DConfDB *db;
} DConfMapping;

static void
dconf_config_split (gchar  *line,
                    gchar **parts,
                    gint   *n_parts)
{
  gint i, n;

  n = i = 0;

  while (n < *n_parts)
    {
      for (i = i; line[i] && line[i] != '#'; i++)
        if (!g_ascii_isspace (line[i]))
          break;

      if (!line[i] || line[i] == '#')
        break;

      parts[n++] = &line[i];

      for (i = i; line[i] && line[i] != '#'; i++)
        if (g_ascii_isspace (line[i]))
          break;

      if (!line[i] || line[i] == '#')
        break;

      line[i++] = '\0';
    }

  *n_parts = n;
}

static gboolean
dconf_config_parse_mount_decl (GSList **mounts,
                               GSList  *mappings,
                               gchar   *line,
                               GError **error)
{
  gchar **db_strings;
  DConfMount *mount;
  gchar *parts[3];
  gint n_parts;
  gint i;
 
  n_parts = 3;
  dconf_config_split (line, parts, &n_parts);

  if (n_parts != 2)
    {
      g_set_error (error, 0, 0,
                   "expected list of files for mount declaration");
      return FALSE;
    }

  if (!g_str_has_suffix (parts[0], "/"))
    {
      g_set_error (error, 0, 0,
                   "mount point '%s' must end in /", parts[0]);
      return FALSE;
    }

  mount = g_slice_new (DConfMount);
  mount->prefix = g_strdup (parts[0]);

  db_strings = g_strsplit (parts[1], ":", 0);
  mount->n_dbs = g_strv_length (db_strings);
  mount->dbs = g_new (DConfDB *, mount->n_dbs);

  for (i = 0; i < mount->n_dbs; i++)
    {
      DConfMapping *mapping = NULL;
      GSList *item;

      for (item = mappings; item; item = item->next)
        {
          mapping = item->data;
          if (strcmp (mapping->name, db_strings[i]) == 0)
            break;
          mapping = NULL;
        }

      if (mapping == NULL)
        {
          g_set_error (error, 0, 0,
                       "mapping for file '%s' has not been declared",
                       db_strings[i]);

          g_strfreev (db_strings);
          g_free (mount->dbs);
          g_slice_free (DConfMount, mount);

          return FALSE;
        }

      mount->dbs[i] = mapping->db;
    }

  *mounts = g_slist_prepend (*mounts, mount);
  g_strfreev (db_strings);

  return TRUE;
}

static gboolean
dconf_config_parse_db_decl (GSList **mappings,
                            gchar   *line,
                            GError **error)
{
  DConfMapping *mapping;
  gchar *parts[3];
  gint n_parts;

  n_parts = 3;
  dconf_config_split (line, parts, &n_parts);

  if (n_parts != 3)
    {
      g_set_error (error, 0, 0,
                   "expected a database name, file path and dbus path");
      return FALSE;
    }

  mapping = g_slice_new (DConfMapping);
  mapping->name = g_strdup (parts[0]);

  mapping->db = g_slice_new (DConfDB);
  mapping->db->reader = NULL;
  mapping->db->bus = NULL;

  mapping->db->filename = g_strdup (parts[1]);
  mapping->db->bus_name = g_strdup (parts[2]);

  *mappings = g_slist_prepend (*mappings, mapping);

  return TRUE;
}

static gboolean
dconf_config_parse_line (GSList **mounts,
                         GSList **mappings,
                         gchar   *line,
                         GError **error)
{
  gchar *hash;

  hash = strchr (line, '#');
  if (hash)
    *hash = '\0';
  g_strstrip (line);

  if (line[0] == '/')
    return dconf_config_parse_mount_decl (mounts, *mappings, line, error);

  else if (line[0])
    return dconf_config_parse_db_decl (mappings, line, error);

  return TRUE;
}

static GSList *
dconf_config_parse_file (const gchar  *filename,
                         GError      **error)
{
  gchar buffer[4096];
  GSList *mappings;
  GSList *mounts;
  FILE *conf;

  conf = fopen (filename, "r");
  g_assert (conf);

  mounts = mappings = NULL;

  while (fgets (buffer, sizeof buffer, conf))
    if (!dconf_config_parse_line (&mounts, &mappings, buffer, error))
      return NULL;

  fclose (conf);

  while (mappings)
    {
      DConfMapping *mapping = mappings->data;

      mappings = g_slist_delete_link (mappings, mappings);
      g_free (mapping->name);
      g_slice_free (DConfMapping, mapping);
    }

  return mounts;
}

GSList *
dconf_config_read (void)
{
  GError *error = NULL;
  gchar *conf_file;
  GSList *mounts;

  conf_file = g_strdup_printf ("%s/dconf/dconf.conf",
                               g_get_user_config_dir ());
  mounts = dconf_config_parse_file (conf_file, &error);
  g_free (conf_file);

  if (mounts == NULL)
    {
      if (error)
        g_error ("failed: %s\n", error->message);
      else
        g_error ("failed with no message");
    }

  return mounts; 
}
