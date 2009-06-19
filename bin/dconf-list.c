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
  gchar **list;
  gint i;

  if (argc != 2 || !dconf_is_path (argv[1]))
    {
      fprintf (stderr, "usage: dconf-list /dconf/path/\n");
      return 1;
    }

  list = dconf_list (argv[1], NULL);

  for (i = 0; list[i]; i++)
    g_print ("%s\n", list[i]);

  return 0;
}
