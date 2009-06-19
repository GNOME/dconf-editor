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

static void
watch_notify (const gchar         *prefix,
              const gchar * const *items,
              gint                 n_items,
              guint32              sequence,
              gpointer             user_data)
{
  if (items[0][0])
    {
      const gchar *comma = "";

      g_print ("%d: %s: ", sequence, prefix);
      while (*items)
        {
          g_print ("%s%s", comma, *items++);
          comma = ", ";
        }
      g_print ("\n");
    }
  else
    {
      g_assert (n_items == 1);

      g_print ("%d: %s\n", sequence, prefix);
    }
}

int
main (int argc, char **argv)
{
  if (argc != 2 ||
      (!dconf_is_key (argv[1]) && !dconf_is_path (argv[1])))
    {
      fprintf (stderr, "usage: dconf-watch /dconf/key\n");
      fprintf (stderr, "or     dconf-watch /dconf/path/\n");
      return 1;
    }

  dconf_watch (argv[1], watch_notify, NULL);

  g_main_loop_run (g_main_loop_new (NULL, FALSE));

  return 0;
}
