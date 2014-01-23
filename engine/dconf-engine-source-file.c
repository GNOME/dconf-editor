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

#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>

static void
dconf_engine_source_file_init (DConfEngineSource *source)
{
  source->bus_type = G_BUS_TYPE_NONE;
  source->bus_name = NULL;
  source->object_path = NULL;
}

static gboolean
dconf_engine_source_file_needs_reopen (DConfEngineSource *source)
{
  return !source->values;
}

static GvdbTable *
dconf_engine_source_file_reopen (DConfEngineSource *source)
{
  GError *error = NULL;
  GvdbTable *table;

  table = gvdb_table_new (source->name, FALSE, &error);

  if (table == NULL)
    {
      if (!source->did_warn)
        {
          g_warning ("unable to open file '%s': %s; expect degraded performance", source->name, error->message);
          source->did_warn = TRUE;
        }

      g_error_free (error);
    }

  return table;
}

static void
dconf_engine_source_file_finalize (DConfEngineSource *source)
{
}

G_GNUC_INTERNAL
const DConfEngineSourceVTable dconf_engine_source_file_vtable = {
  .instance_size    = sizeof (DConfEngineSource),
  .init             = dconf_engine_source_file_init,
  .finalize         = dconf_engine_source_file_finalize,
  .needs_reopen     = dconf_engine_source_file_needs_reopen,
  .reopen           = dconf_engine_source_file_reopen
};
