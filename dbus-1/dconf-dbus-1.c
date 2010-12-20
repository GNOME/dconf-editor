/**
 * Copyright © 2010 Canonical Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the licence, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 **/

#include "dconf-dbus-1.h"

#include <dconf-engine.h>

#include <string.h>

typedef struct _Outstanding Outstanding;

struct _DConfDBusClient
{
  DBusConnection *session_bus;
  DBusConnection *system_bus;
  guint session_filter;
  guint system_filter;
  gint ref_count;

  Outstanding *outstanding;
  gchar *anti_expose_tag;

  DConfEngine *engine;
};

static void
dconf_dbus_client_add_value_to_iter (DBusMessageIter *iter,
                                     GVariant        *value)
{
  GVariantClass class;

  class = g_variant_classify (value);

  switch (class)
    {
    case G_VARIANT_CLASS_BOOLEAN:
      {
        dbus_bool_t boolean;

        boolean = g_variant_get_boolean (value);
        dbus_message_iter_append_basic (iter, 'b', &boolean);
      }
      break;

    case G_VARIANT_CLASS_BYTE:
    case G_VARIANT_CLASS_INT16:
    case G_VARIANT_CLASS_UINT16:
    case G_VARIANT_CLASS_INT32:
    case G_VARIANT_CLASS_UINT32:
    case G_VARIANT_CLASS_INT64:
    case G_VARIANT_CLASS_UINT64:
    case G_VARIANT_CLASS_DOUBLE:
      dbus_message_iter_append_basic (iter, class,
                                      g_variant_get_data (value));
      break;

    case G_VARIANT_CLASS_STRING:
    case G_VARIANT_CLASS_OBJECT_PATH:
    case G_VARIANT_CLASS_SIGNATURE:
      {
        const gchar *str;

        str = g_variant_get_string (value, NULL);
        dbus_message_iter_append_basic (iter, class, &str);
      }
      break;

    case G_VARIANT_CLASS_ARRAY:
      {
        const gchar *contained;
        DBusMessageIter sub;
        gint i, n;

        contained = g_variant_get_type_string (value) + 1;
        n = g_variant_n_children (value);
        dbus_message_iter_open_container (iter, 'a', contained, &sub);
        for (i = 0; i < n; i++)
          {
            GVariant *child;

            child = g_variant_get_child_value (value, i);
            dconf_dbus_client_add_value_to_iter (&sub, child);
            g_variant_unref (child);
          }
          
        dbus_message_iter_close_container (iter, &sub);
      }
      break;

    case G_VARIANT_CLASS_TUPLE:
      {
        DBusMessageIter sub;
        gint i, n;

        n = g_variant_n_children (value);
        dbus_message_iter_open_container (iter, 'r', NULL, &sub);
        for (i = 0; i < n; i++)
          {
            GVariant *child;

            child = g_variant_get_child_value (value, i);
            dconf_dbus_client_add_value_to_iter (&sub, child);
            g_variant_unref (child);
          }
          
        dbus_message_iter_close_container (iter, &sub);
      }
      break;

    case G_VARIANT_CLASS_DICT_ENTRY:
      {
        DBusMessageIter sub;
        gint i;

        dbus_message_iter_open_container (iter, 'e', NULL, &sub);
        for (i = 0; i < 2; i++)
          {
            GVariant *child;

            child = g_variant_get_child_value (value, i);
            dconf_dbus_client_add_value_to_iter (&sub, child);
            g_variant_unref (child);
          }
          
        dbus_message_iter_close_container (iter, &sub);
      }
      break;

    case G_VARIANT_CLASS_VARIANT:
      {
        DBusMessageIter sub;
        GVariant *child;

        child = g_variant_get_variant (value);
        dbus_message_iter_open_container (iter, 'v',
                                          g_variant_get_type_string (child),
                                          &sub);
        dconf_dbus_client_add_value_to_iter (&sub, child);
        dbus_message_iter_close_container (iter, &sub);
        g_variant_unref (child);
      }
      break;

    default:
      g_assert_not_reached ();
    }
}

#if 0
static void
dconf_settings_backend_signal (DBusConnection *connection,
                               const gchar    *sender_name,
                               const gchar    *object_path,
                               const gchar    *interface_name,
                               const gchar    *signal_name,
                               GVariant       *parameters,
                               gpointer        user_data)
{
  DConfDBusClient *dcdbc = user_data;
  const gchar *anti_expose;
  const gchar **rels;
  const gchar *path;
  gchar bus_type;

  if (connection == dcdbc->session_bus)
    {
      anti_expose = dcdbc->anti_expose_tag;
      bus_type = 'e';
    }

  else if (connection == dcdbc->system_bus)
    {
      anti_expose = NULL;
      bus_type = 'y';
    }

  else
    g_assert_not_reached ();

  if (dconf_engine_decode_notify (dcdbc->engine, anti_expose,
                                  &path, &rels, bus_type,
                                  sender_name, interface_name,
                                  signal_name, parameters))
    {
      /** XXX EMIT CHANGES XXX **/
      g_free (rels);
    }
}
#endif

static void
dconf_settings_backend_send (DConfDBusClient               *dcdbc,
                             DConfEngineMessage            *dcem,
                             DBusPendingCallNotifyFunction  callback,
                             gpointer                       user_data)
{
  DBusConnection *connection;
  gint i;

  for (i = 0; i < dcem->n_messages; i++)
    {
      switch (dcem->bus_types[i])
        {
        case 'e':
          connection = dcdbc->session_bus;
          break;

        case 'y':
          connection = dcdbc->system_bus;
          break;

        default:
          g_assert_not_reached ();
        }

      if (connection == NULL && callback != NULL)
        callback (NULL, user_data);

      if (connection != NULL)
        {
          DBusPendingCall *pending;
          DBusMessageIter diter;
          DBusMessage *message;
          GVariantIter giter;
          GVariant *child;

          message = dbus_message_new_method_call (dcem->bus_name,
                                                  dcem->object_path,
                                                  dcem->interface_name,
                                                  dcem->method_name);

          dbus_message_iter_init_append (message, &diter);
          g_variant_iter_init (&giter, dcem->parameters[i]);

          while ((child = g_variant_iter_next_value (&giter)))
            {
              dconf_dbus_client_add_value_to_iter (&diter, child);
              g_variant_unref (child);
            }

          dbus_connection_send_with_reply (connection, message,
                                           &pending, 120000);
          dbus_pending_call_set_notify (pending, callback, user_data, NULL);
          dbus_message_unref (message);
        }
    }
}

static GVariant *
dconf_settings_backend_send_finish (DBusPendingCall *pending)
{
  DBusMessage *message;

  if (pending == NULL)
    return NULL;

  message = dbus_pending_call_steal_reply (pending);
  dbus_pending_call_unref (pending);

  /* XXX remove args */

  dbus_message_unref (message);

  return g_variant_new ("()");
}

struct _Outstanding
{
  Outstanding *next;

  DConfDBusClient *dcdbc;
  DConfEngineMessage    dcem;

  gchar    *set_key;
  GVariant *set_value;
  GTree    *tree;
};

static void
dconf_settings_backend_outstanding_returned (DBusPendingCall *pending,
                                             gpointer         user_data)
{
  Outstanding *outstanding = user_data;
  DConfDBusClient *dcdbc;
  GVariant *reply;

  dcdbc = outstanding->dcdbc;

  /* One way or another we no longer need this hooked into the list.
   */
  {
    Outstanding **tmp;

    for (tmp = &dcdbc->outstanding; tmp; tmp = &(*tmp)->next)
      if (*tmp == outstanding)
        {
          *tmp = outstanding->next;
          break;
        }
  }

  reply = dconf_settings_backend_send_finish (pending);

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
      g_free (dcdbc->anti_expose_tag);
      g_variant_get_child (reply, 0, "s", &dcdbc->anti_expose_tag);
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
          /* XXX emit */;
      else
          /* XXX emit */;
    }

  dconf_engine_message_destroy (&outstanding->dcem);
  dconf_dbus_client_unref (outstanding->dcdbc);
  g_free (outstanding->set_key);

  if (outstanding->set_value)
    g_variant_unref (outstanding->set_value);

  if (outstanding->tree)
    g_tree_unref (outstanding->tree);

  g_slice_free (Outstanding, outstanding);
}

static void
dconf_settings_backend_queue (DConfDBusClient *dcdbc,
                              DConfEngineMessage   *dcem,
                              const gchar          *set_key,
                              GVariant             *set_value,
                              GTree                *tree)
{
  Outstanding *outstanding;

  outstanding = g_slice_new (Outstanding);
  outstanding->dcdbc = dconf_dbus_client_ref (dcdbc);
  outstanding->dcem = *dcem;

  outstanding->set_key = g_strdup (set_key);
  outstanding->set_value = set_value ? g_variant_ref_sink (set_value) : NULL;
  outstanding->tree = tree ? g_tree_ref (tree) : NULL;

  outstanding->next = dcdbc->outstanding;
  dcdbc->outstanding = outstanding;

  dconf_settings_backend_send (outstanding->dcdbc,
                               &outstanding->dcem,
                               dconf_settings_backend_outstanding_returned,
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
dconf_settings_backend_scan_outstanding (DConfDBusClient  *backend,
                                         const gchar           *key,
                                         GVariant             **value)
{
  gboolean found = FALSE;
  Outstanding *node;
  gsize length;

  length = strlen (key);

  if G_LIKELY (backend->outstanding == NULL)
    return FALSE;

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

  return found;
}


GVariant *
dconf_dbus_client_read (DConfDBusClient *dcdbc,
                        const gchar     *key)
{
  GVariant *value;

  if (dconf_settings_backend_scan_outstanding (dcdbc, key, &value))
    return value;

  return dconf_engine_read (dcdbc->engine, key);
}

gboolean
dconf_dbus_client_write (DConfDBusClient *dcdbc,
                         const gchar     *key,
                         GVariant        *value)
{
  DConfEngineMessage dcem;

  if (!dconf_engine_write (dcdbc->engine, key, value, &dcem, NULL))
    return FALSE;

  dconf_settings_backend_queue (dcdbc, &dcem, key, value, NULL);
  /* XXX emit */

  return TRUE;
}

typedef struct
{
  DConfDBusClient *dcdbc;
  guint64 state;
  gchar name[1];
} OutstandingWatch;

static OutstandingWatch *
outstanding_watch_new (DConfDBusClient *dcdbc,
                       const gchar     *name)
{
  OutstandingWatch *watch;
  gsize length;

  length = strlen (name);
  watch = g_malloc (G_STRUCT_OFFSET (OutstandingWatch, name) + length + 1);
  watch->dcdbc = dconf_dbus_client_ref (dcdbc);
  watch->state = dconf_engine_get_state (dcdbc->engine);
  strcpy (watch->name, name);

  return watch;
}

static void
outstanding_watch_free (OutstandingWatch *watch)
{
  dconf_dbus_client_unref (watch->dcdbc);
  g_free (watch);
}

static void
add_match_done (DBusPendingCall *pending,
                gpointer         user_data)
{
  OutstandingWatch *watch = user_data;
  GError *error = NULL;
  GVariant *reply;

  reply = dconf_settings_backend_send_finish (pending);

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
  if (dconf_engine_get_state (watch->dcdbc->engine) != watch->state)
      /* XXX emit watch->name */

  outstanding_watch_free (watch);
}

void
dconf_dbus_client_subscribe (DConfDBusClient *dcdbc,
                             const gchar     *name)
{
  OutstandingWatch *watch;
  DConfEngineMessage dcem;
 
  watch = outstanding_watch_new (dcdbc, name);
  dconf_engine_watch (dcdbc->engine, name, &dcem);
  dconf_settings_backend_send (dcdbc, &dcem, add_match_done, watch);
  dconf_engine_message_destroy (&dcem);
}

void
dconf_dbus_client_unsubscribe (DConfDBusClient *dcdbc,
                               const gchar     *name)
{
  DConfEngineMessage dcem;

  dconf_engine_unwatch (dcdbc->engine, name, &dcem);
  dconf_settings_backend_send (dcdbc, &dcem, NULL, NULL);
  dconf_engine_message_destroy (&dcem);
}

gboolean
dconf_dbus_client_has_pending (DConfDBusClient *dcdbc)
{
  return dcdbc->outstanding != NULL;
}

static GVariant *
dconf_settings_backend_service_func (DConfEngineMessage *dcem)
{
  g_assert_not_reached ();
}

DConfDBusClient *
dconf_dbus_client_new (const gchar    *profile,
                       DBusConnection *system,
                       DBusConnection *session)
{
  DConfDBusClient *dcdbc;

  dconf_engine_set_service_func (dconf_settings_backend_service_func);

  dcdbc = g_slice_new (DConfDBusClient);
  dcdbc->engine = dconf_engine_new (profile);
  dcdbc->system_bus = dbus_connection_ref (system);
  dcdbc->session_bus = dbus_connection_ref (session);
  dcdbc->ref_count = 1;

  return dcdbc;
}

void
dconf_dbus_client_unref (DConfDBusClient *dcdbc)
{
  if (--dcdbc->ref_count == 0)
    {
      dbus_connection_unref (dcdbc->session_bus);
      dbus_connection_unref (dcdbc->system_bus);

      g_slice_free (DConfDBusClient, dcdbc);
    }
}

DConfDBusClient *
dconf_dbus_client_ref (DConfDBusClient *dcdbc)
{
  dcdbc->ref_count++;

  return dcdbc;
}
