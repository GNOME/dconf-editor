/*
 * Copyright © 2010 Codethink Limited
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

#define G_SETTINGS_ENABLE_BACKEND
#include <gio/gsettingsbackend.h>
#include <gio/gio.h>

#include "dconfdatabase.h"

typedef GSettingsBackendClass DConfSettingsBackendClass;

typedef struct
{
  GSettingsBackend backend;

  DConfDatabase *database;
} DConfSettingsBackend;

G_DEFINE_TYPE (DConfSettingsBackend,
               dconf_settings_backend,
               G_TYPE_SETTINGS_BACKEND)

static GVariant *
dconf_settings_backend_read (GSettingsBackend   *backend,
                             const gchar        *key,
                             const GVariantType *expected_type,
                             gboolean            default_value)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  if (default_value)
    return NULL;

  return dconf_database_read (dcsb->database, key);
}

static gchar **
dconf_settings_backend_list (GSettingsBackend   *backend,
                             const gchar        *path,
                             gsize              *length)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  return dconf_database_list (dcsb->database, path, length);
}

static gboolean
dconf_settings_backend_write (GSettingsBackend *backend,
                              const gchar      *path_or_key,
                              GVariant         *value,
                              gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  dconf_database_write (dcsb->database, path_or_key, value, origin_tag);

  return TRUE;
}

static gboolean
dconf_settings_backend_write_tree (GSettingsBackend *backend,
                                   GTree            *tree,
                                   gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  dconf_database_write_tree (dcsb->database, tree, origin_tag);

  return TRUE;
}

static void
dconf_settings_backend_reset (GSettingsBackend *backend,
                              const gchar      *path_or_key,
                              gpointer          origin_tag)
{
  dconf_settings_backend_write (backend, path_or_key, NULL, origin_tag);
}

static gboolean
dconf_settings_backend_get_writable (GSettingsBackend *backend,
                                     const gchar      *key)
{
  return TRUE;
}

static void
dconf_settings_backend_subscribe (GSettingsBackend *backend,
                                  const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  dconf_database_subscribe (dcsb->database, name);
}

static void
dconf_settings_backend_unsubscribe (GSettingsBackend *backend,
                                    const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  dconf_database_unsubscribe (dcsb->database, name);
}

static void
dconf_settings_backend_sync (GSettingsBackend *backend)
{
}

static void
dconf_settings_backend_init (DConfSettingsBackend *dcsb)
{
  dcsb->database = dconf_database_get_for_backend (dcsb);
}

static void
dconf_settings_backend_class_init (GSettingsBackendClass *class)
{
  class->read = dconf_settings_backend_read;
  class->list = dconf_settings_backend_list;
  class->write = dconf_settings_backend_write;
  class->write_keys = dconf_settings_backend_write_tree;
  class->reset = dconf_settings_backend_reset;
  class->reset_path = dconf_settings_backend_reset;
  class->get_writable = dconf_settings_backend_get_writable;
  class->subscribe = dconf_settings_backend_subscribe;
  class->unsubscribe = dconf_settings_backend_unsubscribe;
  class->sync = dconf_settings_backend_sync;
}

void
g_io_module_load (GIOModule *module)
{
  g_type_module_use (G_TYPE_MODULE (module));
  g_io_extension_point_implement (G_SETTINGS_BACKEND_EXTENSION_POINT_NAME,
                                  dconf_settings_backend_get_type (),
                                  "dconf", 100);
}

void
g_io_module_unload (GIOModule *module)
{
  g_assert_not_reached ();
}

gchar **
g_io_module_query (void)
{
  return g_strsplit (",", G_SETTINGS_BACKEND_EXTENSION_POINT_NAME, 0);
}
