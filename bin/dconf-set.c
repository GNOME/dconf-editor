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
  GVariant *value;
  gchar *event_id;

  if (argc != 3 || !dconf_is_key (argv[1]))
    {
      fprintf (stderr, "usage: dconf-set /dconf/key '<gvariant-markup/>'\n");
      return 1;
    }

  value = g_variant_markup_parse (argv[2], -1, NULL, &error);

  if (value == NULL)
    {
      fprintf (stderr, "failed to parse value: %s\n", error->message);
      return 1;
    }

  success = dconf_set (argv[1], value, &event_id, &error);
  g_variant_unref (value);
  
  if (success)
    {
      g_print ("%s\n", event_id);
      g_free (event_id);
      return 0;
    }
  else
    {
      fprintf (stderr, "failed to set: %s\n", error->message);
      return 2;
    }
}
