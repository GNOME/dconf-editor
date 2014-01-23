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

#include "../shm/dconf-shm.h"
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>

typedef struct
{
  DConfEngineSource source;

  guint8 *shm;
} DConfEngineSourceUser;

static GvdbTable *
dconf_engine_source_user_open_gvdb (const gchar *name)
{
  GvdbTable *table;
  gchar *filename;

  /* This can fail in the normal case of the user not having any
   * settings.  That's OK and it shouldn't be considered as an error.
   */
  filename = g_build_filename (g_get_user_config_dir (), "dconf", name, NULL);
  table = gvdb_table_new (filename, FALSE, NULL);
  g_free (filename);

  return table;
}

static void
dconf_engine_source_user_init (DConfEngineSource *source)
{
  source->bus_type = G_BUS_TYPE_SESSION;
  source->bus_name = g_strdup ("ca.desrt.dconf");
  source->object_path = g_strdup_printf ("/ca/desrt/dconf/Writer/%s", source->name);
  source->writable = TRUE;
}

static gboolean
dconf_engine_source_user_needs_reopen (DConfEngineSource *source)
{
  DConfEngineSourceUser *user_source = (DConfEngineSourceUser *) source;

  return dconf_shm_is_flagged (user_source->shm);
}

static GvdbTable *
dconf_engine_source_user_reopen (DConfEngineSource *source)
{
  DConfEngineSourceUser *user_source = (DConfEngineSourceUser *) source;

  dconf_shm_close (user_source->shm);
  user_source->shm = dconf_shm_open (source->name);

  return dconf_engine_source_user_open_gvdb (source->name);
}

static void
dconf_engine_source_user_finalize (DConfEngineSource *source)
{
  DConfEngineSourceUser *user_source = (DConfEngineSourceUser *) source;

  dconf_shm_close (user_source->shm);
}

G_GNUC_INTERNAL
const DConfEngineSourceVTable dconf_engine_source_user_vtable = {
  .instance_size    = sizeof (DConfEngineSourceUser),
  .init             = dconf_engine_source_user_init,
  .finalize         = dconf_engine_source_user_finalize,
  .needs_reopen     = dconf_engine_source_user_needs_reopen,
  .reopen           = dconf_engine_source_user_reopen
};
