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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "config.h"

#define G_SETTINGS_ENABLE_BACKEND
#include <gio/gsettingsbackend.h>
#include "../engine/dconf-engine.h"
#include <gio/gio.h>

#include <string.h>

typedef GSettingsBackendClass DConfSettingsBackendClass;

typedef struct
{
  GSettingsBackend backend;
  DConfEngine     *engine;
} DConfSettingsBackend;

static GType dconf_settings_backend_get_type (void);
G_DEFINE_TYPE (DConfSettingsBackend, dconf_settings_backend, G_TYPE_SETTINGS_BACKEND)

static GVariant *
dconf_settings_backend_read (GSettingsBackend   *backend,
                             const gchar        *key,
                             const GVariantType *expected_type,
                             gboolean            default_value)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  GVariant *value;

  if (default_value)
    {
      GQueue *read_through;

      /* Mark the key as having been reset when trying to do the read... */
      read_through = g_queue_new ();
      g_queue_push_tail (read_through, dconf_changeset_new_write (key, NULL));
      value = dconf_engine_read (dcsb->engine, read_through, key);
      g_queue_free_full (read_through, (GDestroyNotify) dconf_changeset_unref);
    }

  else
    value = dconf_engine_read (dcsb->engine, NULL, key);

  return value;
}

static GVariant *
dconf_settings_backend_read_user_value (GSettingsBackend   *backend,
                                        const gchar        *key,
                                        const GVariantType *expected_type)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  return dconf_engine_read_user_value (dcsb->engine, NULL, key);
}

static gboolean
dconf_settings_backend_write (GSettingsBackend *backend,
                              const gchar      *key,
                              GVariant         *value,
                              gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfChangeset *change;
  gboolean success;

  change = dconf_changeset_new ();
  dconf_changeset_set (change, key, value);

  success = dconf_engine_change_fast (dcsb->engine, change, origin_tag, NULL);
  dconf_changeset_unref (change);

  return success;
}

static gboolean
dconf_settings_backend_add_to_changeset (gpointer key,
                                         gpointer value,
                                         gpointer data)
{
  dconf_changeset_set (data, key, value);

  return FALSE;
}

static gboolean
dconf_settings_backend_write_tree (GSettingsBackend *backend,
                                   GTree            *tree,
                                   gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfChangeset *change;
  gboolean success;

  if (g_tree_nnodes (tree) == 0)
    return TRUE;

  change = dconf_changeset_new ();
  g_tree_foreach (tree, dconf_settings_backend_add_to_changeset, change);
  success = dconf_engine_change_fast (dcsb->engine, change, origin_tag, NULL);
  dconf_changeset_unref (change);

  return success;
}

static void
dconf_settings_backend_reset (GSettingsBackend *backend,
                              const gchar      *key,
                              gpointer          origin_tag)
{
  dconf_settings_backend_write (backend, key, NULL, origin_tag);
}

static gboolean
dconf_settings_backend_get_writable (GSettingsBackend *backend,
                                     const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  return dconf_engine_is_writable (dcsb->engine, name);
}

static void
dconf_settings_backend_subscribe (GSettingsBackend *backend,
                                  const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  dconf_engine_watch_fast (dcsb->engine, name);
}

static void
dconf_settings_backend_unsubscribe (GSettingsBackend *backend,
                                    const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  dconf_engine_unwatch_fast (dcsb->engine, name);
}

static void
dconf_settings_backend_sync (GSettingsBackend *backend)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  dconf_engine_sync (dcsb->engine);
}

static void
dconf_settings_backend_free_weak_ref (gpointer data)
{
  GWeakRef *weak_ref = data;

  g_weak_ref_clear (weak_ref);
  g_slice_free (GWeakRef, weak_ref);
}

static void
dconf_settings_backend_init (DConfSettingsBackend *dcsb)
{
  GWeakRef *weak_ref;

  weak_ref = g_slice_new (GWeakRef);
  g_weak_ref_init (weak_ref, dcsb);
  dcsb->engine = dconf_engine_new (NULL, weak_ref, dconf_settings_backend_free_weak_ref);
}

static void
dconf_settings_backend_finalize (GObject *object)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) object;

  dconf_engine_unref (dcsb->engine);

  G_OBJECT_CLASS (dconf_settings_backend_parent_class)
    ->finalize (object);
}

static void
dconf_settings_backend_class_init (GSettingsBackendClass *class)
{
  GObjectClass *object_class = G_OBJECT_CLASS (class);

  object_class->finalize = dconf_settings_backend_finalize;

  class->read = dconf_settings_backend_read;
  class->read_user_value = dconf_settings_backend_read_user_value;
  class->write = dconf_settings_backend_write;
  class->write_tree = dconf_settings_backend_write_tree;
  class->reset = dconf_settings_backend_reset;
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
  return g_strsplit (G_SETTINGS_BACKEND_EXTENSION_POINT_NAME, "!", 0);
}

void
dconf_engine_change_notify (DConfEngine         *engine,
                            const gchar         *prefix,
                            const gchar * const *changes,
                            const gchar         *tag,
                            gboolean             is_writability,
                            gpointer             origin_tag,
                            gpointer             user_data)
{
  GWeakRef *weak_ref = user_data;
  DConfSettingsBackend *dcsb;

  dcsb = g_weak_ref_get (weak_ref);

  if (dcsb == NULL)
    return;

  if (changes[0] == NULL)
    return;

  if (is_writability)
    {
      /* We know that the engine does it this way... */
      g_assert (changes[0][0] == '\0' && changes[1] == NULL);

      if (g_str_has_suffix (prefix, "/"))
        g_settings_backend_path_writable_changed (G_SETTINGS_BACKEND (dcsb), prefix);
      else
        g_settings_backend_writable_changed (G_SETTINGS_BACKEND (dcsb), prefix);
    }

  /* We send the normal change notification even in the event that this
   * was a writability notification because adding/removing a lock could
   * impact the value that gets read.
   */
  if (changes[1] == NULL)
    {
      if (g_str_has_suffix (prefix, "/"))
        g_settings_backend_path_changed (G_SETTINGS_BACKEND (dcsb), prefix, origin_tag);
      else
        g_settings_backend_changed (G_SETTINGS_BACKEND (dcsb), prefix, origin_tag);
    }
  else
    g_settings_backend_keys_changed (G_SETTINGS_BACKEND (dcsb), prefix, changes, origin_tag);
}
