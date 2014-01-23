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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "config.h"

#include "dconf-engine-source-private.h"

#include <string.h>

void
dconf_engine_source_free (DConfEngineSource *source)
{
  if (source->values)
    gvdb_table_free (source->values);

  if (source->locks)
    gvdb_table_free (source->locks);

  source->vtable->finalize (source);
  g_free (source->bus_name);
  g_free (source->object_path);
  g_free (source->name);
  g_free (source);
}

gboolean
dconf_engine_source_refresh (DConfEngineSource *source)
{
  if (source->vtable->needs_reopen (source))
    {
      gboolean was_open;
      gboolean is_open;

      /* Record if we had a gvdb before or not. */
      was_open = source->values != NULL;

      g_clear_pointer (&source->values, gvdb_table_free);
      g_clear_pointer (&source->locks, gvdb_table_free);

      source->values = source->vtable->reopen (source);
      if (source->values)
        source->locks = gvdb_table_get_table (source->values, ".locks");

      /* Check if we ended up with a gvdb. */
      is_open = source->values != NULL;

      /* Only return TRUE in the case that we either had a database
       * before or ended up with one after.  In the case that we just go
       * from NULL to NULL, return FALSE.
       */
      return was_open || is_open;
    }

  return FALSE;
}

DConfEngineSource *
dconf_engine_source_new (const gchar *description)
{
  const DConfEngineSourceVTable *vtable;
  DConfEngineSource *source;
  const gchar *colon;

  /* Source descriptions are of the form
   *
   *   type:name
   *
   * Where type must currently be one of "user-db" or "system-db".
   *
   * We first find the colon.
   */
  colon = strchr (description, ':');

  /* Ensure that we have a colon and that a database name follows it. */
  if (colon == NULL || colon[1] == '\0')
    return NULL;

  /* Check if the part before the colon is "user-db"... */
  if ((colon == description + 7) && memcmp (description, "user-db", 7) == 0)
    vtable = &dconf_engine_source_user_vtable;

  /* ...or "service-db" */
  else if ((colon == description + 10) && memcmp (description, "service-db", 10) == 0)
    vtable = &dconf_engine_source_service_vtable;

  /* ...or "system-db" */
  else if ((colon == description + 9) && memcmp (description, "system-db", 9) == 0)
    vtable = &dconf_engine_source_system_vtable;

  /* ...or "file-db" */
  else if ((colon == description + 7) && memcmp (description, "file-db", 7) == 0)
    vtable = &dconf_engine_source_file_vtable;

  /* If it's not any of those, we have failed. */
  else
    return NULL;

  /* We have had a successful parse.
   *
   *  - either user-db: or system-db:
   *  - non-NULL and non-empty database name
   *
   * Create the source.
   */
  source = g_malloc0 (vtable->instance_size);
  source->vtable = vtable;
  source->name = g_strdup (colon + 1);
  source->vtable->init (source);

  return source;
}

DConfEngineSource *
dconf_engine_source_new_default (void)
{
  DConfEngineSource *source;

  source = g_malloc0 (dconf_engine_source_user_vtable.instance_size);
  source->vtable = &dconf_engine_source_user_vtable;
  source->name = g_strdup ("user");
  source->vtable->init (source);

  return source;
}
