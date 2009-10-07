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

#include "dconf-config.h"

#include <string.h>
#include <stdio.h>
#include <errno.h>

typedef struct
{
  gchar *name;
  DConfDB *db;
} DConfMapping;

static gboolean
dconf_config_parse_mount_decl (GSList **mounts,
                               GSList  *mappings,
                               gint     argc,
                               gchar  **argv,
                               GError **error)
{
  gchar **db_strings;
  DConfMount *mount;
  gint i;
 
  if (argc != 2)
    {
      g_set_error (error, G_SHELL_ERROR, G_SHELL_ERROR_FAILED,
                   "expected list of databases for mount declaration");
      return FALSE;
    }

  if (!g_str_has_suffix (argv[0], "/"))
    {
      g_set_error (error, G_SHELL_ERROR, G_SHELL_ERROR_FAILED,
                   "mount point '%s' must end in /", argv[0]);
      return FALSE;
    }

  mount = g_slice_new (DConfMount);
  mount->prefix = g_strdup (argv[0]);

  db_strings = g_strsplit (argv[1], ":", 0);
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

static gchar *
dconf_config_expand_path (const gchar *path)
{
  if (path[0] == '~' && path[1] == '/')
    return g_strdup_printf ("%s/%s", g_get_home_dir (), path + 2);
  else
    return g_strdup (path);
}

static gboolean
dconf_config_parse_db_decl (GSList **mappings,
                            gint     argc,
                            gchar  **argv,
                            GError **error)
{
  DConfMapping *mapping;

  if (argc != 3)
    {
      g_set_error (error, 0, 0,
                   "expected a database name, file path and dbus location");
      return FALSE;
    }

  mapping = g_slice_new (DConfMapping);
  mapping->name = g_strdup (argv[0]);

  mapping->db = g_slice_new (DConfDB);
  mapping->db->reader = NULL;
  mapping->db->bus = NULL;

  mapping->db->filename = dconf_config_expand_path (argv[1]);
  mapping->db->bus_name = g_strdup (argv[2]);

  *mappings = g_slist_prepend (*mappings, mapping);

  return TRUE;
}

static GSList *
dconf_config_parse_file (GError **error)
{
  GSList *mappings = NULL;
  GSList *mounts = NULL;
  gchar buffer[1024];
  FILE *file;
  gchar *tmp;
  gint line;

  tmp = g_strdup (DCONF_CONF);
  file = fopen (tmp, "r");

  if (file == NULL)
    {
      gint saved_errno = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "Cannot open dconf config file %s: %s",
                   tmp, g_strerror (saved_errno));
      g_free (tmp);

      return NULL;
    }

  line = 0;
  while (fgets (buffer, sizeof buffer, file))
    {
      GError *my_error = NULL;
      gboolean success;
      gchar **argv;
      gint argc;

      line++;

      if (strlen (buffer) > 1000)
        {
          g_set_error (error, G_SHELL_ERROR, G_SHELL_ERROR_FAILED,
                       "%s:%d: excessively long line", tmp, line);
          fclose (file);
          g_free (tmp);

          return NULL;
        }

      if (!g_shell_parse_argv (buffer, &argc, &argv, &my_error))
        {
          if (my_error->domain == G_SHELL_ERROR &&
              my_error->code == G_SHELL_ERROR_EMPTY_STRING)
            {
              g_clear_error (&my_error);
              continue;
            }

          g_propagate_prefixed_error (error, my_error, "%s:%d: ", tmp, line);
          fclose (file);
          g_free (tmp);

          return NULL;
        }

      if (argv[0][0] == '/')
        success = dconf_config_parse_mount_decl (&mounts, mappings,
                                                 argc, argv, error);
      else
        success = dconf_config_parse_db_decl (&mappings, argc, argv, error);

      g_strfreev (argv);

      if (!success)
        {
          g_prefix_error (error, "%s:%d: ", tmp, line);
          fclose (file);
          g_free (tmp);

          return NULL;
        }
    }

  fclose (file);

  if (mounts == NULL)
    g_set_error (error, G_SHELL_ERROR, G_SHELL_ERROR_FAILED,
                 "%s: no mountpoints declared", tmp);

  g_free (tmp);

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
  GSList *mounts;

  mounts = dconf_config_parse_file (&error);

  if (mounts == NULL)
    g_error ("failed: %s\n", error->message);

  return mounts; 
}
