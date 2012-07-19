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

#include "dconf-engine-profile.h"

#include <string.h>
#include <stdio.h>

#include "dconf-engine-source.h"

/* This comment attempts to document the exact semantics of
 * profile-loading.
 *
 * In no situation should the result of profile loading be an abort.
 * There must be a defined outcome for all possible situations.
 * Warnings may be issued to stderr, however.
 *
 * The first step is to determine what profile is to be used.  If a
 * profile is explicitly specified by the API then it has the top
 * priority.  Otherwise, if the DCONF_PROFILE environment variable is
 * set, it takes next priority.
 *
 * In both of those cases, if the named profile starts with a slash
 * character then it is taken to be an absolute pathname.  If it does
 * not start with a slash then it is assumed to specify a profile file
 * relative to /etc/dconf/profile/ (ie: DCONF_PROFILE=test for profile
 * file /etc/dconf/profile/test).
 *
 * If opening the profile file fails then the null profile is used.
 * This is a profile that contains zero sources.  All keys will be
 * unwritable and all reads will return NULL.
 *
 * In the case that no explicit profile was given and DCONF_PROFILE is
 * unset, dconf attempts to open and use a profile called "user" (ie:
 * profile file /etc/dconf/profile/user).  If that fails then the
 * fallback is to act as if the profile file existed and contained a
 * single line: "user-db:user".
 *
 * Note that the fallback case for a missing profile file is different
 * in the case where a profile was explicitly specified (either by the
 * API or the environment) and the case where one was not.
 *
 * Once a profile file is opened, each line is treated as a possible
 * source.  Comments and empty lines are ignored.
 *
 * All valid source specification lines need to start with 'user-db:' or
 * 'system-db:'.  If a line doesn't start with one of these then it gets
 * ignored.  If all the lines in the file get ignored then the result is
 * effectively the null profile.
 *
 * If the first source is a "user-db:" then the resulting profile will
 * be writable.  No profile starting with a "system-db:" source can ever
 * be writable.
 *
 * Note: even if the source fails to initialise (due to a missing file,
 * for example) it will remain in the source list.  This could have a
 * performance cost: in the case of a system-db, for example, dconf will
 * check if the file has come into existence on every read.
 */

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
  sources[0] = dconf_engine_source_new_default ();
  *n_sources = 1;

  return sources;
}

static DConfEngineSource *
dconf_engine_profile_handle_line (gchar *line)
{
  DConfEngineSource *source;
  gchar *end;

  /* remove whitespace at the front */
  while (g_ascii_isspace (*line))
    line++;

  /* find the end of the line (or start of comments) */
  end = line + strcspn (line, "#\n");

  /* remove whitespace at the end */
  while (end > line && g_ascii_isspace (end[-1]))
    end--;

  /* if we're left with nothing, return NULL */
  if (line == end)
    return NULL;

  *end = '\0';

  source = dconf_engine_source_new (line);

  if (source == NULL)
    g_warning ("unknown dconf database description: %s", line);

  return source;
}

static DConfEngineSource **
dconf_engine_read_profile_file (FILE *file,
                                gint *n_sources)
{
  DConfEngineSource **sources;
  gchar line[80];
  gint n = 0, a;

  sources = g_new (DConfEngineSource *, (a = 4));

  while (fgets (line, sizeof line, file))
    {
      DConfEngineSource *source;

      /* The input file has long lines. */
      if G_UNLIKELY (!strchr (line, '\n'))
        {
          GString *long_line;

          long_line = g_string_new (line);
          while (fgets (line, sizeof line, file))
            {
              g_string_append (long_line, line);
              if (strchr (line, '\n'))
                break;
            }

          source = dconf_engine_profile_handle_line (long_line->str);
          g_string_free (long_line, TRUE);
        }

      else
        source = dconf_engine_profile_handle_line (line);

      if (source != NULL)
        {
          if (n == a)
            sources = g_renew (DConfEngineSource *, sources, a *= 2);

          sources[n++] = source;
        }
    }

  *n_sources = n;

  return g_realloc_n (sources, n, sizeof (DConfEngineSource *));
}

DConfEngineSource **
dconf_engine_profile_open (const gchar *profile,
                           gint        *n_sources)
{
  DConfEngineSource **sources;
  FILE *file;

  if (profile == NULL)
    profile = g_getenv ("DCONF_PROFILE");

  if (profile == NULL)
    {
      file = fopen ("/etc/dconf/profile/user", "r");

      /* Only in the case that no profile was specified do we use this
       * fallback.
       */
      if (file == NULL)
        return dconf_engine_default_profile (n_sources);
    }
  else if (profile[0] != '/')
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
