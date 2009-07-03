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

#include <dconf.h>
#include <stdio.h>

int
main (int argc, char **argv)
{
  GError *error = NULL;
  gboolean success;
  gchar *event_id;

  if (argc != 2 ||
      (!dconf_is_key (argv[1]) && !dconf_is_path (argv[1])))
    {
      fprintf (stderr, "usage: dconf-reset /dconf/key\n");
      fprintf (stderr, "or     dconf-reset /dconf/path/\n");
      return 1;
    }

  success = dconf_reset (argv[1], &event_id, &error);
  
  if (success)
    {
      g_print ("%s\n", event_id);
      g_free (event_id);
      return 0;
    }
  else
    {
      fprintf (stderr, "failed to reset: %s\n", error->message);
      return 2;
    }
}
