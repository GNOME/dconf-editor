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

#include "dconf-writer-config.h"

#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <glib.h>

static gchar *
dconf_writer_config_expand_path (const gchar *path)
{
  if (path[0] == '~' && path[1] == '/')
    return g_strdup_printf ("%s/%s", g_get_home_dir (), path + 2);
  else
    return g_strdup (path);
}

gboolean
dconf_writer_config_read (const gchar         *name,
                          DConfWriterBusType  *bus_type,
                          gchar              **bus_name,
                          gchar              **filename,
                          GError             **error)
{
  char buffer[1024];
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

      return FALSE;
    }

  line = 0;
  while (fgets (buffer, sizeof buffer, file))
    {
      GError *my_error = NULL;
      gchar **argv;
      gint argc;

      line++;

      if (strlen (buffer) > 1000)
        {
          g_set_error (error, G_SHELL_ERROR, G_SHELL_ERROR_FAILED,
                       "%s:%d: excessively long line", tmp, line);
          fclose (file);
          g_free (tmp);

          return FALSE;
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

          return FALSE;
        }

      if (strcmp (argv[0], name) == 0)
        {
          fclose (file);

          if (argc != 3)
            {
              g_set_error (error, G_SHELL_ERROR, G_SHELL_ERROR_FAILED,
                           "%s:%d: database declaration must have 3 parts",
                           tmp, line);
              g_strfreev (argv);
              g_free (tmp);

              return FALSE;
            }

          if (g_str_has_prefix (argv[2], "session/"))
            {
              *bus_type = DCONF_WRITER_SESSION_BUS;
              *bus_name = g_strdup (argv[2] + 8);
            }

          else if (g_str_has_prefix (argv[2], "system/"))
            {
              *bus_type = DCONF_WRITER_SYSTEM_BUS;
              *bus_name = g_strdup (argv[2] + 7);
            }

          else
            {
              g_set_error (error, G_SHELL_ERROR, G_SHELL_ERROR_FAILED,
                           "%s:%d: dbus location designation must start "
                           "with 'session/' or 'system/'", tmp, line);
              g_strfreev (argv);
              g_free (tmp);

              return FALSE;
             }

          *filename = dconf_writer_config_expand_path (argv[1]);
          g_strfreev (argv);
          g_free (tmp);

          return TRUE;
        }

      g_strfreev (argv);
    }

  g_set_error (error, G_SHELL_ERROR, G_SHELL_ERROR_FAILED,
               "%s: no database declaration for '%s'", tmp, name);
  fclose (file);
  g_free (tmp);

  return FALSE;
}
