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

  GDBusConnection *session_bus;
  gchar *session_anti_expose;
  GDBusConnection *system_bus;
  gchar *system_anti_expose;

  Outstanding *outstanding;
  GCond *sync_cond;
} DConfSettingsBackend;

static GType dconf_settings_backend_get_type (void);
G_DEFINE_TYPE (DConfSettingsBackend,
               dconf_settings_backend,
               G_TYPE_SETTINGS_BACKEND)


struct _Outstanding
{
  Outstanding *next;

  DConfEngineMessage dcem;
  volatile guint32 serial;

  gchar *set_key;
  GVariant *set_value;

  GTree *tree;
};

static volatile guint32 *
dconf_settings_backend_new_outstanding (DConfSettingsBackend *dcsb,
                                        DConfEngineMessage   *dcem,
                                        const gchar          *set_key,
                                        GVariant             *set_value,
                                        GTree                *tree)
{
  Outstanding *outstanding;

  outstanding = g_slice_new (Outstanding);
  outstanding->set_key = NULL;
  outstanding->dcem = *dcem;

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
dconf_settings_backend_remove_outstanding (DConfSettingsBackend  *dcsb,
                                           guint                  bus_type,
                                           GDBusMessage          *message,
                                           gchar                **anti_expose)
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

        if (dcsb->outstanding == NULL && dcsb->sync_cond != NULL)
          g_cond_signal (dcsb->sync_cond);

        g_static_mutex_unlock (&dcsb->lock);

        g_free (tmp->set_key);

        if (tmp->set_value)
          g_variant_unref (tmp->set_value);

        if (tmp->tree)
          g_tree_unref (tmp->tree);

        if (*anti_expose)
          {
            g_free (*anti_expose);
            *anti_expose = NULL;
          }

        dconf_engine_interpret_reply (&tmp->dcem,
                                      g_dbus_message_get_sender (message),
                                      g_dbus_message_get_body (message),
                                      anti_expose, NULL);

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
      if (node->set_key)
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

static void
dconf_settings_backend_incoming_signal (DConfSettingsBackend  *dcsb,
                                        guint                  bt,
                                        GDBusMessage          *message,
                                        gchar                **anti_expose)
{
  const gchar **rels;
  const gchar *path;

  if (dconf_engine_decode_notify (dcsb->engine, *anti_expose,
                                  &path, &rels, bt,
                                  g_dbus_message_get_sender (message),
                                  g_dbus_message_get_interface (message),
                                  g_dbus_message_get_member (message),
                                  g_dbus_message_get_body (message)))
    {
      GSettingsBackend *backend = G_SETTINGS_BACKEND (dcsb);

      if (!g_str_has_suffix (path, "/"))
        g_settings_backend_changed (backend, path, NULL);

      else if (rels[0] == NULL)
        g_settings_backend_path_changed (backend, path, NULL);

      else
        g_settings_backend_keys_changed (backend, path, rels, NULL);

      g_free (*anti_expose);
      *anti_expose = NULL;
      g_free (rels);
    }
}

static GDBusMessage *
dconf_settings_backend_filter (GDBusConnection *connection,
                               GDBusMessage    *message,
                               gboolean         is_incoming,
                               gpointer         user_data)
{
  DConfSettingsBackend *dcsb = user_data;
  guint bus_type;
  gchar **ae;

  if (!is_incoming)
    return message;

  if (connection == dcsb->session_bus)
    {
      ae = &dcsb->session_anti_expose;
      bus_type = 'e';
    }
  else if (connection == dcsb->system_bus)
    {
      ae = &dcsb->system_anti_expose;
      bus_type = 'y';
    }

  else
    g_assert_not_reached ();

  switch (g_dbus_message_get_message_type (message))
    {
    case G_DBUS_MESSAGE_TYPE_METHOD_RETURN:
      if (dconf_settings_backend_remove_outstanding (dcsb, bus_type,
                                                     message, ae))
        {
          /* consume message */
          g_object_unref (message);
          return NULL;
        }

    case G_DBUS_MESSAGE_TYPE_SIGNAL:
      dconf_settings_backend_incoming_signal (dcsb, bus_type, message, ae);

    default:
      return message;
    }
}

static GVariant *
dconf_settings_backend_read (GSettingsBackend   *backend,
                             const gchar        *key,
                             const GVariantType *expected_type,
                             gboolean            default_value)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  if (!default_value)
    {
      GVariant *value;

      if (dconf_settings_backend_scan_outstanding (dcsb, key, &value))
        return value;

      return dconf_engine_read (dcsb->engine, key);
    }
  else
    return dconf_engine_read_default (dcsb->engine, key);
}

static void
dconf_settings_backend_send (GDBusConnection    *bus,
                             DConfEngineMessage *dcem,
                             volatile guint32   *serial)
{
  GDBusMessage *message;
  GVariant *body;

  message = g_dbus_message_new_method_call (dcem->destination,
                                            dcem->object_path,
                                            dcem->interface,
                                            dcem->method);
  body = g_variant_get_child_value (dcem->body, 0);
  g_dbus_message_set_body (message, body);
  g_variant_unref (body);

  if (serial)
    g_dbus_connection_send_message (bus, message, G_DBUS_SEND_MESSAGE_FLAGS_NONE, serial, NULL);
  else
    g_dbus_connection_send_message_with_reply_sync (bus, message, G_DBUS_SEND_MESSAGE_FLAGS_NONE,
                                                    -1, NULL, NULL, NULL);

  g_variant_unref (dcem->body);
  g_object_unref (message);
}

static gboolean
dconf_settings_backend_get_bus (DConfSettingsBackend  *dcsb,
                                GDBusConnection      **bus,
                                DConfEngineMessage    *dcem)
{
  switch (dcem->bus_type)
    {
    case 'e':
      if (dcsb->session_bus == NULL)
        {
          g_static_mutex_lock (&dcsb->lock);
          if (dcsb->session_bus == NULL)
            {
              dcsb->session_bus = g_bus_get_sync (G_BUS_TYPE_SESSION,
                                                  NULL, NULL);
              g_dbus_connection_add_filter (dcsb->session_bus,
                                            dconf_settings_backend_filter,
                                            dcsb, NULL);
            }

          g_static_mutex_unlock (&dcsb->lock);
        }

      *bus = dcsb->session_bus;
      break;

    case 'y':
      if (dcsb->system_bus == NULL)
        {
          g_static_mutex_lock (&dcsb->lock);
          if (dcsb->system_bus == NULL)
            {
              dcsb->system_bus = g_bus_get_sync (G_BUS_TYPE_SYSTEM,
                                                  NULL, NULL);
              g_dbus_connection_add_filter (dcsb->session_bus,
                                            dconf_settings_backend_filter,
                                            dcsb, NULL);
            }
          g_static_mutex_unlock (&dcsb->lock);
        }

      *bus = dcsb->system_bus;
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
                              const gchar      *key,
                              GVariant         *value,
                              gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  volatile guint32 *serial;
  DConfEngineMessage dcem;
  GDBusConnection *bus;

  if (!dconf_engine_write (dcsb->engine, key, value, &dcem, NULL))
    return FALSE;

  if (!dconf_settings_backend_get_bus (dcsb, &bus, &dcem))
    return FALSE;

  serial = dconf_settings_backend_new_outstanding (dcsb, &dcem, key,
                                                   value, NULL);
  dconf_settings_backend_send (bus, &dcem, serial);

  g_settings_backend_changed (backend, key, origin_tag);

  return TRUE;
}

static gboolean
dconf_settings_backend_write_tree (GSettingsBackend *backend,
                                   GTree            *tree,
                                   gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  volatile guint32 *serial;
  DConfEngineMessage dcem;
  GDBusConnection *bus;
  const gchar **keys;
  GVariant **values;
  gchar *prefix;

  g_settings_backend_flatten_tree (tree, &prefix, &keys, &values);

  if (dconf_engine_write_many (dcsb->engine,
                               prefix, keys, values, &dcem, NULL))
    {
      if (dconf_settings_backend_get_bus (dcsb, &bus, &dcem))
        {
          serial = dconf_settings_backend_new_outstanding (dcsb, &dcem,
                                                           NULL, NULL, tree);

          dconf_settings_backend_send (bus, &dcem, serial);

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
  DConfEngineMessage dcem;
  GDBusConnection *bus;

  dconf_engine_watch (dcsb->engine, name, &dcem);

  if (dconf_settings_backend_get_bus (dcsb, &bus, &dcem))
    dconf_settings_backend_send (bus, &dcem, NULL);
}

static void
dconf_settings_backend_unsubscribe (GSettingsBackend *backend,
                                    const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage dcem;
  GDBusConnection *bus;

  dconf_engine_unwatch (dcsb->engine, name, &dcem);

  if (dconf_settings_backend_get_bus (dcsb, &bus, &dcem))
    dconf_settings_backend_send (bus, &dcem, NULL);
}

static void
dconf_settings_backend_sync (GSettingsBackend *backend)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  if (!dcsb->outstanding)
    return;

  g_static_mutex_lock (&dcsb->lock);

  g_assert (dcsb->sync_cond == NULL);
  dcsb->sync_cond = g_cond_new ();

  while (dcsb->outstanding)
    g_cond_wait (dcsb->sync_cond, g_static_mutex_get_mutex (&dcsb->lock));

  g_cond_free (dcsb->sync_cond);
  dcsb->sync_cond = NULL;

  g_static_mutex_unlock (&dcsb->lock);
}

static GVariant *
dconf_settings_backend_service_func (DConfEngineMessage *dcem)
{
  g_assert (dcem->bus_type == 'e');

  return g_dbus_connection_call_sync (g_bus_get_sync (G_BUS_TYPE_SESSION,
                                                      NULL, NULL),
                                      dcem->destination, dcem->object_path,
                                      dcem->interface, dcem->method,
                                      dcem->body, dcem->reply_type,
                                      0, -1, NULL, NULL);
}

static void
dconf_settings_backend_init (DConfSettingsBackend *dcsb)
{
  dconf_engine_set_service_func (dconf_settings_backend_service_func);
  dcsb->engine = dconf_engine_new (NULL);
}

static void
dconf_settings_backend_class_init (GSettingsBackendClass *class)
{
  class->read = dconf_settings_backend_read;
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
