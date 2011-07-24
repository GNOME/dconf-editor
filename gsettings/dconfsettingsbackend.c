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

#include "dconfcontext.h"

typedef GSettingsBackendClass DConfSettingsBackendClass;
typedef struct _Outstanding Outstanding;

typedef struct
{
  GSettingsBackend backend;

  GDBusConnection *session_bus;
  GDBusConnection *system_bus;
  guint session_subscription;
  guint system_subscription;

  Outstanding *outstanding;
  gchar *anti_expose_tag;

  DConfEngine *engine;
  GStaticMutex lock;
  GCond *sync_cond;
} DConfSettingsBackend;

static GType dconf_settings_backend_get_type (void);
G_DEFINE_TYPE (DConfSettingsBackend,
               dconf_settings_backend,
               G_TYPE_SETTINGS_BACKEND)

static void
dconf_settings_backend_signal (GDBusConnection *connection,
                               const gchar     *sender_name,
                               const gchar     *object_path,
                               const gchar     *interface_name,
                               const gchar     *signal_name,
                               GVariant        *parameters,
                               gpointer         user_data)
{
  DConfSettingsBackend *dcsb = user_data;
  const gchar *anti_expose;
  const gchar **rels;
  const gchar *path;
  gchar bus_type;

  if (connection == dcsb->session_bus)
    {
      anti_expose = dcsb->anti_expose_tag;
      bus_type = 'e';
    }

  else if (connection == dcsb->system_bus)
    {
      anti_expose = NULL;
      bus_type = 'y';
    }

  else
    g_assert_not_reached ();

  if (dconf_engine_decode_notify (dcsb->engine, anti_expose,
                                  &path, &rels, bus_type,
                                  sender_name, interface_name,
                                  signal_name, parameters))
    {
      GSettingsBackend *backend = G_SETTINGS_BACKEND (dcsb);

      if (!g_str_has_suffix (path, "/"))
        g_settings_backend_changed (backend, path, NULL);

      else if (rels[0] == NULL)
        g_settings_backend_path_changed (backend, path, NULL);

      else
        g_settings_backend_keys_changed (backend, path, rels, NULL);

      g_free (rels);
    }

  if (dconf_engine_decode_writability_notify (&path, interface_name,
                                              signal_name, parameters))
    {
      GSettingsBackend *backend = G_SETTINGS_BACKEND (dcsb);

      if (g_str_has_suffix (path, "/"))
        {
          g_settings_backend_path_writable_changed (backend, path);
          g_settings_backend_path_changed (backend, path, NULL);
        }

      else
        {
          g_settings_backend_writable_changed (backend, path);
          g_settings_backend_changed (backend, path, NULL);
        }
    }
}

static void
dconf_settings_backend_send (DConfSettingsBackend *dcsb,
                             DConfEngineMessage   *dcem,
                             GAsyncReadyCallback   callback,
                             gpointer              user_data)
{
  GDBusConnection *connection;
  gint i;

  for (i = 0; i < dcem->n_messages; i++)
    {
      switch (dcem->bus_types[i])
        {
        case 'e':
          if (dcsb->session_bus == NULL && callback)
            {
              dcsb->session_bus =
                g_bus_get_sync (G_BUS_TYPE_SESSION, NULL, NULL);

              if (dcsb->session_bus != NULL)
                dcsb->session_subscription =
                  g_dbus_connection_signal_subscribe (dcsb->session_bus, NULL,
                                                      "ca.desrt.dconf.Writer",
                                                      NULL, NULL, NULL,
                                                      G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
                                                      dconf_settings_backend_signal,
                                                      dcsb, NULL);
            }
          connection = dcsb->session_bus;
          break;

        case 'y':
          if (dcsb->system_bus == NULL && callback)
            {
              dcsb->system_bus =
                g_bus_get_sync (G_BUS_TYPE_SYSTEM, NULL, NULL);

              if (dcsb->system_bus != NULL)
                dcsb->system_subscription =
                  g_dbus_connection_signal_subscribe (dcsb->system_bus, NULL,
                                                      "ca.desrt.dconf.Writer",
                                                      NULL, NULL, NULL,
                                                      G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
                                                      dconf_settings_backend_signal,
                                                      dcsb, NULL);
            }
          connection = dcsb->system_bus;
          break;

        default:
          g_assert_not_reached ();
        }

      if (connection == NULL && callback != NULL)
        callback (NULL, NULL, user_data);

      if (connection != NULL)
        g_dbus_connection_call (connection,
                                dcem->bus_name,
                                dcem->object_path,
                                dcem->interface_name,
                                dcem->method_name,
                                dcem->parameters[i],
                                dcem->reply_type,
                                0, 120000, NULL, callback, user_data);
    }
}

static GVariant *
dconf_settings_backend_send_finish (GObject      *source,
                                    GAsyncResult *result)
{
  if (source == NULL)
    return NULL;

  return g_dbus_connection_call_finish (G_DBUS_CONNECTION (source),
                                        result, NULL);
}

struct _Outstanding
{
  Outstanding *next;

  DConfSettingsBackend *dcsb;
  DConfEngineMessage    dcem;

  gchar    *set_key;
  GVariant *set_value;
  GTree    *tree;
};

static void
dconf_settings_backend_outstanding_returned (GObject      *source,
                                             GAsyncResult *result,
                                             gpointer      user_data)
{
  Outstanding *outstanding = user_data;
  DConfSettingsBackend *dcsb;
  GVariant *reply;

  dcsb = outstanding->dcsb;

  /* One way or another we no longer need this hooked into the list.
   */
  g_static_mutex_lock (&dcsb->lock);
  {
    Outstanding **tmp;

    for (tmp = &dcsb->outstanding; tmp; tmp = &(*tmp)->next)
      if (*tmp == outstanding)
        {
          *tmp = outstanding->next;
          break;
        }

    if (dcsb->outstanding == NULL && dcsb->sync_cond)
      g_cond_broadcast (dcsb->sync_cond);
  }
  g_static_mutex_unlock (&dcsb->lock);

  reply = dconf_settings_backend_send_finish (source, result);

  if (reply)
    {
      /* Success.
       *
       * We want to ensure that we don't emit an extra change
       * notification signal when we see the signal that the service is
       * about to send, so store the tag so we know to ignore it when
       * the signal comes.
       *
       * No thread safety issue here since this variable is only
       * accessed from the worker thread.
       */
      g_free (dcsb->anti_expose_tag);
      g_variant_get_child (reply, 0, "s", &dcsb->anti_expose_tag);
      g_variant_unref (reply);
    }
  else
    {
      /* An error of some kind.
       *
       * We already removed the outstanding entry from the list, so the
       * unmodified database is now visible to the client.  Change
       * notify so that they see it.
       */
      if (outstanding->set_key)
        g_settings_backend_changed (G_SETTINGS_BACKEND (dcsb),
                                    outstanding->set_key, NULL);

      else
        g_settings_backend_changed_tree (G_SETTINGS_BACKEND (dcsb),
                                         outstanding->tree, NULL);
    }

  dconf_engine_message_destroy (&outstanding->dcem);
  g_object_unref (outstanding->dcsb);
  g_free (outstanding->set_key);

  if (outstanding->set_value)
    g_variant_unref (outstanding->set_value);

  if (outstanding->tree)
    g_tree_unref (outstanding->tree);

  g_slice_free (Outstanding, outstanding);
}

static gboolean
dconf_settings_backend_send_outstanding (gpointer data)
{
  Outstanding *outstanding = data;

  dconf_settings_backend_send (outstanding->dcsb,
                               &outstanding->dcem,
                               dconf_settings_backend_outstanding_returned,
                               outstanding);

  return FALSE;
}

static void
dconf_settings_backend_queue (DConfSettingsBackend *dcsb,
                              DConfEngineMessage   *dcem,
                              const gchar          *set_key,
                              GVariant             *set_value,
                              GTree                *tree)
{
  Outstanding *outstanding;

  outstanding = g_slice_new (Outstanding);
  outstanding->dcsb = g_object_ref (dcsb);
  outstanding->dcem = *dcem;

  outstanding->set_key = g_strdup (set_key);
  outstanding->set_value = set_value ? g_variant_ref_sink (set_value) : NULL;
  outstanding->tree = tree ? g_tree_ref (tree) : NULL;

  g_static_mutex_lock (&dcsb->lock);
  outstanding->next = dcsb->outstanding;
  dcsb->outstanding = outstanding;
  g_static_mutex_unlock (&dcsb->lock);

  g_main_context_invoke (dconf_context_get (),
                         dconf_settings_backend_send_outstanding,
                         outstanding);
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

static gboolean
dconf_settings_backend_write (GSettingsBackend *backend,
                              const gchar      *key,
                              GVariant         *value,
                              gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage dcem;

  if (!dconf_engine_write (dcsb->engine, key, value, &dcem, NULL))
    return FALSE;

  dconf_settings_backend_queue (dcsb, &dcem, key, value, NULL);
  g_settings_backend_changed (backend, key, origin_tag);

  return TRUE;
}

static gboolean
dconf_settings_backend_write_tree (GSettingsBackend *backend,
                                   GTree            *tree,
                                   gpointer          origin_tag)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage dcem;
  const gchar **keys;
  GVariant **values;
  gboolean success;
  gchar *prefix;

  g_settings_backend_flatten_tree (tree, &prefix, &keys, &values);

  if ((success = dconf_engine_write_many (dcsb->engine, prefix,
                                          keys, values, &dcem, NULL)))
    {
      dconf_settings_backend_queue (dcsb, &dcem, NULL, NULL, tree);
      g_settings_backend_keys_changed (backend, prefix, keys, origin_tag);
    }

  g_free (prefix);
  g_free (values);
  g_free (keys);

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

typedef struct
{
  DConfSettingsBackend *dcsb;
  guint64 state;
  gchar *name;
  gint outstanding;
} OutstandingWatch;

static OutstandingWatch *
outstanding_watch_new (DConfSettingsBackend *dcsb,
                       const gchar          *name)
{
  OutstandingWatch *watch;

  watch = g_slice_new (OutstandingWatch);
  watch->dcsb = g_object_ref (dcsb);
  watch->state = dconf_engine_get_state (dcsb->engine);
  watch->outstanding = 0;
  watch->name = g_strdup (name);

  return watch;
}

static void
outstanding_watch_free (OutstandingWatch *watch)
{
  if (--watch->outstanding == 0)
    {
      g_object_unref (watch->dcsb);
      g_free (watch->name);

      g_slice_free (OutstandingWatch, watch);
    }
}

static void
add_match_done (GObject      *source,
                GAsyncResult *result,
                gpointer      user_data)
{
  OutstandingWatch *watch = user_data;
  GError *error = NULL;
  GVariant *reply;

  /* couldn't connect to DBus */
  if (source == NULL)
    {
      outstanding_watch_free (watch);
      return;
    }

  reply = g_dbus_connection_call_finish (G_DBUS_CONNECTION (source),
                                         result, &error);

  if (reply == NULL)
    {
      g_critical ("DBus AddMatch for dconf path '%s': %s",
                  watch->name, error->message);
      outstanding_watch_free (watch);
      g_error_free (error);

      return;
    }

  else
    g_variant_unref (reply); /* it is just an empty tuple */

  /* In the normal case we can just free everything and be done.
   *
   * There is a fleeting chance, however, that the database has changed
   * in the meantime.  In that case we can only assume that the subject
   * of this watch changed in that time period and emit a signal to that
   * effect.
   */
  if (dconf_engine_get_state (watch->dcsb->engine) != watch->state)
    g_settings_backend_path_changed (G_SETTINGS_BACKEND (watch->dcsb),
                                     watch->name, NULL);

  outstanding_watch_free (watch);
}

static gboolean
dconf_settings_backend_subscribe_context_func (gpointer data)
{
  OutstandingWatch *watch = data;
  DConfEngineMessage dcem;

  dconf_engine_watch (watch->dcsb->engine, watch->name, &dcem);
  watch->outstanding = dcem.n_messages;

  dconf_settings_backend_send (watch->dcsb, &dcem, add_match_done, watch);
  dconf_engine_message_destroy (&dcem);

  return FALSE;
}

static void
dconf_settings_backend_subscribe (GSettingsBackend *backend,
                                  const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;

  g_main_context_invoke (dconf_context_get (),
                         dconf_settings_backend_subscribe_context_func,
                         outstanding_watch_new (dcsb, name));
}

static void
dconf_settings_backend_unsubscribe (GSettingsBackend *backend,
                                    const gchar      *name)
{
  DConfSettingsBackend *dcsb = (DConfSettingsBackend *) backend;
  DConfEngineMessage dcem;

  dconf_engine_unwatch (dcsb->engine, name, &dcem);
  dconf_settings_backend_send (dcsb, &dcem, NULL, NULL);
  dconf_engine_message_destroy (&dcem);
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
  g_assert (dcem->bus_types[0] == 'e');

  return g_dbus_connection_call_sync (g_bus_get_sync (G_BUS_TYPE_SESSION,
                                                      NULL, NULL),
                                      dcem->bus_name, dcem->object_path,
                                      dcem->interface_name, dcem->method_name,
                                      dcem->parameters[0], dcem->reply_type,
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
