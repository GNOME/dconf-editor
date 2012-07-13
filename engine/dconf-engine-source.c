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

#include "dconf-engine-source-private.h"

#include <string.h>

void
dconf_engine_source_free (DConfEngineSource *source)
{
  if (source->values)
    gvdb_table_unref (source->values);

  if (source->locks)
    gvdb_table_unref (source->locks);

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
      g_clear_pointer (&source->values, gvdb_table_unref);
      g_clear_pointer (&source->locks, gvdb_table_unref);

      source->values = source->vtable->reopen (source);
      if (source->values)
        source->locks = gvdb_table_get_table (source->values, ".locks");

      return TRUE;
    }

  return FALSE;
}

DConfEngineSource *
dconf_engine_source_new (const gchar *description)
{
  const DConfEngineSourceVTable *vtable;
  DConfEngineSource *source;

  switch (description[0])
    {
    case 's':
      vtable = &dconf_engine_source_system_vtable;
      break;

    case 'u':
      vtable = &dconf_engine_source_user_vtable;
      break;

    default:
      g_warning ("unknown dconf database description: %s", description);
      return NULL;
    }

  source = g_malloc0 (vtable->instance_size);
  source->vtable = vtable;
  source->name = strchr (description, ':');
  if (source->name)
    source->name = g_strdup (source->name + 1);
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
