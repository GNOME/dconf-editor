/*
 * Copyright © 2010 Codethink Limited
 * Copyright © 2012 Canonical Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the licence, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "dconf-engine.h"

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "dconf-engine-source.h"

static DConfEngineSource **
dconf_engine_null_profile (gint *n_sources)
{
  *n_sources = 0;

  return NULL;
}

static DConfEngineSource **
dconf_engine_default_profile (gint *n_sources)
{
  DConfEngineSource **sources;

  sources = g_new (DConfEngineSource *, 1);
  sources[0] = dconf_engine_source_new ("user-db:user");
  *n_sources = 1;

  return sources;
}

static DConfEngineSource **
dconf_engine_read_profile_file (FILE *file,
                                gint *n_sources)
{
  DConfEngineSource **sources;
  gchar line[80];
  gint n = 0, a;

  sources = g_new (DConfEngineSource *, (a = 16));

  while (fgets (line, sizeof line, file))
    {
      DConfEngineSource *source;
      gchar *end;

      end = strchr (line, '\n');

      if (end == NULL)
        {
          g_warning ("ignoring long or unterminated line in dconf profile");

          /* skip until we find the newline or EOF */
          while (fgets (line, sizeof line, file) && !strchr (line, '\n'));

          continue;
        }

      if (end == line)
        continue;

      if (line[0] == '#')
        continue;

      *end = '\0';

      source = dconf_engine_source_new (line);

      if (source != NULL)
        {
          if (n == a)
            sources = g_renew (DConfEngineSource *, sources, a *= 2);

          sources[n++] = source;
        }
    }

  return sources;
}

DConfEngineSource **
dconf_engine_profile_get_default (gint *n_sources)
{
  DConfEngineSource **sources;
  const gchar *profile;
  FILE *file;

  profile = getenv ("DCONF_PROFILE");

  if (profile == NULL)
    return dconf_engine_default_profile (n_sources);

  if (profile[0] != '/')
    {
      gchar *filename = g_build_filename ("/etc/dconf/profile", profile, NULL);
      file = fopen (filename, "r");
      g_free (filename);
    }
  else
    file = fopen (profile, "r");

  if (file != NULL)
    {
      sources = dconf_engine_read_profile_file (file, n_sources);
      fclose (file);
    }
  else
    {
      g_warning ("unable to open named profile (%s): using the null configuration.", profile);
      sources = dconf_engine_null_profile (n_sources);
    }

  return sources;
}
