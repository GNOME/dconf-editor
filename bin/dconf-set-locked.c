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

#include <string.h>
#include <dconf.h>
#include <stdio.h>

static gboolean
parse_bool (const gchar *string,
            gboolean    *value)
{
  if (strcasecmp (string, "true") == 0 ||
      strcasecmp (string, "t") == 0 ||
      strcmp (string, "1") == 0)
    {
      *value = TRUE;
      return TRUE;
    }

  if (strcasecmp (string, "false") == 0 ||
      strcasecmp (string, "f") == 0 ||
      strcmp (string, "0") == 0)
    {
      *value = FALSE;
      return TRUE;
    }

  return FALSE;
}

int
main (int argc, char **argv)
{
  GError *error = NULL;
  gboolean locked;

  if (argc != 3 ||
      (!dconf_is_key (argv[1]) && !dconf_is_path (argv[1])) ||
      !parse_bool (argv[2], &locked))
    {
      fprintf (stderr, "usage: dconf-set-locked /dconf/key [boolean]\n");
      fprintf (stderr, "or     dconf-set-locked /dconf/path/ [boolean]\n");
      return 1;
    }

  if (!dconf_set_locked (argv[1], locked, &error))
    {
      fprintf (stderr, "failed to reset: %s\n", error->message);
      return 2;
    }

  return 0;
}
