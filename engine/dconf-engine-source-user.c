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

#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>

typedef struct
{
  DConfEngineSource source;

  guint8 *shm;
} DConfEngineSourceUser;

static guint8 *
dconf_engine_source_user_open_shm (const gchar *name)
{
  static gchar *shmdir;
  gchar *filename;
  void *memory;
  gint fd;

  if (g_once_init_enter (&shmdir))
    g_once_init_leave (&shmdir, g_build_filename (g_get_user_runtime_dir (), "dconf", NULL));

  filename = g_build_filename (shmdir, name, NULL);
  memory = NULL;
  fd = -1;

  if (g_mkdir_with_parents (shmdir, 0700) != 0)
    {
      g_critical ("unable to create directory '%s': %s.  dconf will not work properly.", shmdir, g_strerror (errno));
      goto out;
    }

  fd = open (filename, O_RDWR | O_CREAT, 0600);
  if (fd == -1)
    {
      g_critical ("unable to create file '%s': %s.  dconf will not work properly.", filename, g_strerror (errno));
      goto out;
    }

  if (ftruncate (fd, 1) != 0)
    {
      g_critical ("failed to allocate file '%s': %s.  dconf will not work properly.", filename, g_strerror (errno));
      goto out;
    }

  memory = mmap (NULL, 1, PROT_READ, MAP_SHARED, fd, 0);
  g_assert (memory != NULL);

  if (memory == MAP_FAILED)
    {
      g_critical ("failed to mmap file '%s': %s.  dconf will not work properly.", filename, g_strerror (errno));
      memory = NULL;
      goto out;
    }

 out:
  g_free (filename);
  close (fd);

  return memory;
}

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

static gboolean
dconf_engine_source_user_init (DConfEngineSource *source)
{
  DConfEngineSourceUser *user_source = (DConfEngineSourceUser *) source;
  guint8 *shm;

  shm = dconf_engine_source_user_open_shm (source->name);

  if (shm == NULL)
    return FALSE;

  source->bus_type = G_BUS_TYPE_SESSION;
  source->bus_name = g_strdup ("ca.desrt.dconf");
  source->object_path = g_strdup_printf ("/ca/desrt/dconf/Writer/%s", source->name);
  source->writable = TRUE;
  user_source->shm = shm;

  source->values = dconf_engine_source_user_open_gvdb (source->name);

  return TRUE;
}

static gboolean
dconf_engine_source_user_needs_reopen (DConfEngineSource *source)
{
  DConfEngineSourceUser *user_source = (DConfEngineSourceUser *) source;

  return user_source->shm && *user_source->shm;
}

static GvdbTable *
dconf_engine_source_user_reopen (DConfEngineSource *source)
{
  DConfEngineSourceUser *user_source = (DConfEngineSourceUser *) source;

  munmap (user_source->shm, 1);
  user_source->shm = dconf_engine_source_user_open_shm (source->name);

  if (user_source->shm)
    return dconf_engine_source_user_open_gvdb (source->name);

  return NULL;
}

static void
dconf_engine_source_user_finalize (DConfEngineSource *source)
{
  DConfEngineSourceUser *user_source = (DConfEngineSourceUser *) source;

  if (user_source->shm)
    munmap (user_source->shm, 1);
}

G_GNUC_INTERNAL
const DConfEngineSourceVTable dconf_engine_source_user_vtable = {
  .instance_size    = sizeof (DConfEngineSourceUser),
  .init             = dconf_engine_source_user_init,
  .finalize         = dconf_engine_source_user_finalize,
  .needs_reopen     = dconf_engine_source_user_needs_reopen,
  .reopen           = dconf_engine_source_user_reopen
};
