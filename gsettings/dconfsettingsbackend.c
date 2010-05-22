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
#include <dconf-engine.h>
#include <gio/gio.h>

#include <string.h>

typedef GSettingsBackendClass DConfSettingsBackendClass;
typedef struct _Outstanding Outstanding;

typedef struct
{
  GSettingsBackend backend;
  GStaticMutex lock;

  DConfEngine *engine;

  Outstanding *outstanding;
  GDBusConnection *bus;
  guint64 anti_expose;
} DConfSettingsBackend;

G_DEFINE_TYPE (DConfSettingsBackend,
               dconf_settings_backend,
               G_TYPE_SETTINGS_BACKEND)


struct _Outstanding
{
  Outstanding *next;

  volatile guint32 serial;

  gchar *reset_path, *set_key;
  GVariant *set_value;

  GTree *tree;
};

static volatile guint32 *
dconf_settings_backend_new_outstanding (DConfSettingsBackend *dcsb,
                                        const gchar          *set_key,
                                        GVariant             *set_value,
                                        GTree                *tree)
{
  Outstanding *outstanding;

  outstanding = g_slice_new (Outstanding);
  outstanding->reset_path = NULL;
  outstanding->set_key = NULL;

  if (!set_key || g_str_has_suffix (set_key, "/"))
    {
      g_assert (set_value == NULL);
      outstanding->reset_path = g_strdup (set_key);
    }
  else
    outstanding->set_key = g_strdup (set_key);

  outstanding->serial = 0;

  if (set_value)
    outstanding->set_value = g_variant_ref_sink (set_value);
  else
    outstanding->set_value = NULL;

  if (tree)
    outstanding->tree = g_tree_ref (tree);
  else
    outstanding->tree = NULL;

  g_static_mutex_lock (&dcsb->lock);
  outstanding->next = dcsb->outstanding;
  dcsb->outstanding = outstanding;
  g_static_mutex_unlock (&dcsb->lock);

  return &outstanding->serial;
}

static gboolean
dconf_settings_backend_remove_outstanding (DConfSettingsBackend *dcsb,
                                           GDBusMessage         *message,
                                           guint64              *anti_expose)
{
  gboolean found = FALSE;
  Outstanding **node;
  guint32 serial;

  if G_LIKELY (dcsb->outstanding == NULL)
    return FALSE;

  serial = g_dbus_message_get_reply_serial (message);

  if (serial == 0)
    return FALSE;

  g_static_mutex_lock (&dcsb->lock);

  /* this could be made more asymptotically efficient by using a queue
   * or a double-linked list with a 'tail' pointer but the usual case
   * here will be one outstanding item and very rarely more than a few.
   *
   * so we scan...
   */
  for (node = &dcsb->outstanding; *node; node = &(*node)->next)
    if ((*node)->serial == serial)
      {
        Outstanding *tmp;

        tmp = *node;
        *node = tmp->next;

        g_static_mutex_unlock (&dcsb->lock);

        g_variant_get (g_dbus_message_get_body (message), "(t)", anti_expose);

        g_free (tmp->reset_path);
        g_free (tmp->set_key);

        if (tmp->set_value)
          g_variant_unref (tmp->set_value);

        if (tmp->tree)
          g_tree_unref (tmp->tree);

        found = TRUE;
        break;
      }

  g_static_mutex_unlock (&dcsb->lock);

  return found;
}

static gboolean
dconf_settings_backend_scan_outstanding_tree (GTree       *tree,
                                              const gchar *key,
                                              gsize        key_length,
                                              gpointer    *value)
{
  gchar *mykey;

  mykey = g_alloca (key_length + 1);
  memcpy (mykey, key, key_length + 1);

  while (!g_tree_lookup_extended (tree, mykey, NULL, value) &&
         --key_length)
    {
      while (mykey[key_length - 1] != '/')
        key_length--;

      mykey[key_length] = '\0';
    }

  return key_length != 0;
}

static gboolean
dconf_settings_backend_scan_outstanding (DConfSettingsBackend  *backend,
                                         const gchar           *key,
                                         GVariant             **value)
{
  gboolean found = FALSE;
  Outstanding *node;
  gsize length;

  length = strlen (key);

  if G_LIKELY (backend->outstanding == NULL)
    return FALSE;

  g_static_mutex_lock (&backend->lock);

  for (node = backend->outstanding; node; node = node->next)
    {
      if (node->reset_path)
        {
          if (g_str_has_prefix (key, node->reset_path))
            {
              *value = NULL;
              found = TRUE;
              break;
            }
        }

      else if (node->set_key)
        {
          if (strcmp (key, node->set_key) == 0)
            {
              if (node->set_value != NULL)
                *value = g_variant_ref (node->set_value);
              else
                *value = NULL;

              found = TRUE;
              break;
            }
        }

      else
        {
          gpointer result;

          if (dconf_settings_backend_scan_outstanding_tree (node->tree, key,
                                                    length, &result))
            {
              if (result)
                *value = g_variant_ref (result);
              else
                *value = NULL;

              found = TRUE;
              break;
            }
        }
    }

  g_static_mutex_unlock (&backend->lock);

  return found;
}

static GVariant *
dconf_settings_backend_read (GSettingsBackend   *backend,
                             const gchar        *key,
                             const GVariantType *expected_type,
                             gboolean            default_value)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfReadType type;

  if (!default_value)
    {
      GVariant *value;

      if (dconf_settings_backend_scan_outstanding (dcsb, key, &value))
        return value;

      type = DCONF_READ_NORMAL;
    }
  else
    type = DCONF_READ_RESET;

  return dconf_engine_read (dcsb->engine, key, type);
}

static void
dconf_settings_backend_send (GDBusConnection    *bus,
                             DConfEngineMessage *dcem,
                             volatile guint32   *serial)
{
  GDBusMessage *message;

  message = g_dbus_message_new_method_call (dcem->destination,
                                            dcem->object_path,
                                            dcem->interface,
                                            dcem->method);
  g_dbus_message_set_body (message, dcem->body);

  if (serial)
    g_dbus_connection_send_message (bus, message, serial, NULL);
  else
    g_dbus_connection_send_message_with_reply_sync (bus, message, -1,
                                                    NULL, NULL, NULL);

  g_variant_unref (dcem->body);
  g_object_unref (message);
}

static gboolean
dconf_settings_backend_get_bus (GDBusConnection    **bus,
                                DConfEngineMessage  *dcem)
{
  switch (dcem->bus_type)
    {
    case 'e':
      *bus = g_bus_get_sync (G_BUS_TYPE_SESSION, NULL, NULL);
      break;

    case 'y':
      *bus = g_bus_get_sync (G_BUS_TYPE_SYSTEM, NULL, NULL);
      break;

    default:
      g_assert_not_reached ();
    }

  if (*bus == NULL && dcem->body)
    g_variant_unref (dcem->body);

  return *bus != NULL;
}

static gboolean
dconf_settings_backend_write (GSettingsBackend *backend,
                              const gchar      *path_or_key,
                              GVariant         *value,
                              gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage message;
  volatile guint32 *serial;
  GDBusConnection *bus;

  if (!dconf_engine_write (dcsb->engine, &message, path_or_key, value))
    return FALSE;

  if (!dconf_settings_backend_get_bus (&bus, &message))
    return FALSE;

  serial = dconf_settings_backend_new_outstanding (dcsb,
                                                   path_or_key,
                                                   value,
                                                   NULL);

  dconf_settings_backend_send (bus, &message, serial);

  if (g_str_has_suffix (path_or_key, "/"))
    g_settings_backend_changed_path (backend, path_or_key, origin_tag);
  else
    g_settings_backend_changed (backend, path_or_key, origin_tag);

  return TRUE;
}

static gboolean
dconf_settings_backend_write_tree (GSettingsBackend *backend,
                                   GTree            *tree,
                                   gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage message;
  volatile guint32 *serial;
  GDBusConnection *bus;
  const gchar **keys;
  GVariant **values;
  gchar *prefix;

  g_settings_backend_flatten_tree (tree, &prefix, &keys, &values);

  if (dconf_engine_write_many (dcsb->engine, &message, prefix, keys, values))
    {
      if (dconf_settings_backend_get_bus (&bus, &message))
        {
          serial = dconf_settings_backend_new_outstanding (dcsb, NULL,
                                                           NULL, tree);

          dconf_settings_backend_send (bus, &message, serial);

          g_settings_backend_keys_changed (backend, prefix, keys, origin_tag);

          return TRUE;
        }
    }

  g_free (prefix);
  g_free (values);
  g_free (keys);

  return FALSE;
}

static void
dconf_settings_backend_reset (GSettingsBackend *backend,
                              const gchar      *path_or_key,
                              gpointer          origin_tag)
{
  g_assert_not_reached ();
}

static gboolean
dconf_settings_backend_get_writable (GSettingsBackend *backend,
                                     const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage message;
  GDBusConnection *bus;

  if (!dconf_engine_is_writable (dcsb->engine, &message, name))
    return FALSE;

  return dconf_settings_backend_get_bus (&bus, &message);
}

static void
dconf_settings_backend_subscribe (GSettingsBackend *backend,
                                  const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage message;
  GDBusConnection *bus;

  dconf_engine_watch (dcsb->engine, &message, name);

  if (dconf_settings_backend_get_bus (&bus, &message))
    dconf_settings_backend_send (bus, &message, NULL);
}

static void
dconf_settings_backend_unsubscribe (GSettingsBackend *backend,
                                    const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage message;
  GDBusConnection *bus;

  dconf_engine_unwatch (dcsb->engine, &message, name);

  if (dconf_settings_backend_get_bus (&bus, &message))
    dconf_settings_backend_send (bus, &message, NULL);
}

static void
dconf_settings_backend_sync (GSettingsBackend *backend)
{
}

static void
dconf_settings_backend_init (DConfSettingsBackend *dcsb)
{
  dcsb->engine = dconf_engine_new (NULL);
}

static void
dconf_settings_backend_class_init (GSettingsBackendClass *class)
{
  class->read = dconf_settings_backend_read;
  // class->list = dconf_settings_backend_list;
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
  return g_strsplit (G_SETTINGS_BACKEND_EXTENSION_POINT_NAME, "!", 0);
}
