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

#include "dconf-engine.h"
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static void
dconf_engine_source_service_init (DConfEngineSource *source)
{
  source->bus_type = G_BUS_TYPE_SESSION;
  source->bus_name = g_strdup ("ca.desrt.dconf");
  source->object_path = g_strdup_printf ("/ca/desrt/dconf/%s", source->name);
  source->writable = TRUE;
}

static gboolean
dconf_engine_source_service_needs_reopen (DConfEngineSource *source)
{
  return !source->values || !gvdb_table_is_valid (source->values);
}

static GvdbTable *
dconf_engine_source_service_reopen (DConfEngineSource *source)
{
  static gboolean did_warn;
  GError *error = NULL;
  GvdbTable *table;
  gchar *filename;

  filename = g_build_filename (g_get_user_runtime_dir (), "dconf-service", source->name, NULL);

  /* If the file does not exist, kick the service to have it created. */
  if (access (filename, R_OK) != 0)
    dconf_engine_dbus_call_sync_func (source->bus_type, source->bus_name, source->object_path,
                                      "ca.desrt.dconf.Writer", "Init", NULL, NULL, NULL);

  table = gvdb_table_new (filename, FALSE, &error);

  if (table == NULL)
    {
      if (!did_warn)
        {
          g_critical ("unable to open file '%s': %s; expect degraded performance", filename, error->message);
          did_warn = TRUE;
        }

      g_error_free (error);
    }

  g_free (filename);

  return table;
}

static void
dconf_engine_source_service_finalize (DConfEngineSource *source)
{
}

G_GNUC_INTERNAL
const DConfEngineSourceVTable dconf_engine_source_service_vtable = {
  .instance_size    = sizeof (DConfEngineSource),
  .init             = dconf_engine_source_service_init,
  .finalize         = dconf_engine_source_service_finalize,
  .needs_reopen     = dconf_engine_source_service_needs_reopen,
  .reopen           = dconf_engine_source_service_reopen
};
