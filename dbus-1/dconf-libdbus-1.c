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

#include "config.h"

#include "dconf-libdbus-1.h"

#include "../engine/dconf-engine.h"

#include <string.h>

static DBusConnection *dconf_libdbus_1_buses[5];

struct _DConfDBusClient
{
  DConfEngine *engine;
  GSList *watches;
  gint ref_count;
};

#define DCONF_LIBDBUS_1_ERROR (g_quark_from_static_string("DCONF_LIBDBUS_1_ERROR"))
#define DCONF_LIBDBUS_1_ERROR_FAILED 0

static DBusMessage *
dconf_libdbus_1_new_method_call (const gchar *bus_name,
                                 const gchar *object_path,
                                 const gchar *interface_name,
                                 const gchar *method_name,
                                 GVariant    *parameters)
{
  DBusMessageIter dbus_iter;
  DBusMessage *message;
  GVariantIter iter;
  GVariant *child;

  g_variant_ref_sink (parameters);

  message = dbus_message_new_method_call (bus_name, object_path, interface_name, method_name);
  dbus_message_iter_init_append (message, &dbus_iter);
  g_variant_iter_init (&iter, parameters);

  while ((child = g_variant_iter_next_value (&iter)))
    {
      if (g_variant_is_of_type (child, G_VARIANT_TYPE_STRING))
        {
          const gchar *str;

          str = g_variant_get_string (child, NULL);
          dbus_message_iter_append_basic (&dbus_iter, DBUS_TYPE_STRING, &str);
        }

      else if (g_variant_is_of_type (child, G_VARIANT_TYPE_UINT32))
        {
          guint32 uint;

          uint = g_variant_get_uint32 (child);
          dbus_message_iter_append_basic (&dbus_iter, DBUS_TYPE_UINT32, &uint);
        }

      else
        {
          DBusMessageIter subiter;
          const guint8 *bytes;
          gsize n_elements;

          g_assert (g_variant_is_of_type (child, G_VARIANT_TYPE_BYTESTRING));

          bytes = g_variant_get_fixed_array (child, &n_elements, sizeof (guint8));
          dbus_message_iter_open_container (&dbus_iter, DBUS_TYPE_ARRAY, "y", &subiter);
          dbus_message_iter_append_fixed_array (&subiter, DBUS_TYPE_BYTE, &bytes, n_elements);
          dbus_message_iter_close_container (&dbus_iter, &subiter);
        }

      g_variant_unref (child);
    }

  g_variant_unref (parameters);

  return message;
}

static GVariant *
dconf_libdbus_1_get_message_body (DBusMessage  *message,
                                  GError      **error)
{
  GVariantBuilder builder;
  const gchar *signature;
  DBusMessageIter iter;

  /* We support two types: strings and arrays of strings.
   *
   * It's very simple to detect if the message contains only these
   * types: check that the signature contains only the letters "a" and
   * "s" and that it does not contain "aa".
   */
  signature = dbus_message_get_signature (message);
  if (signature[strspn(signature, "as")] != '\0' || strstr (signature, "aa"))
    {
      g_set_error (error, DCONF_LIBDBUS_1_ERROR, DCONF_LIBDBUS_1_ERROR_FAILED,
                   "unable to handle message type '(%s)'", signature);
      return NULL;
    }

  g_variant_builder_init (&builder, G_VARIANT_TYPE_TUPLE);
  dbus_message_iter_init (message, &iter);
  while (dbus_message_iter_get_arg_type (&iter))
    {
      const gchar *string;

      if (dbus_message_iter_get_arg_type (&iter) == DBUS_TYPE_STRING)
        {
          dbus_message_iter_get_basic (&iter, &string);
          g_variant_builder_add (&builder, "s", string);
        }
      else
        {
          DBusMessageIter sub;

          g_assert (dbus_message_iter_get_arg_type (&iter) == DBUS_TYPE_ARRAY &&
                    dbus_message_iter_get_element_type (&iter) == DBUS_TYPE_STRING);

          g_variant_builder_open (&builder, G_VARIANT_TYPE_STRING_ARRAY);
          dbus_message_iter_recurse (&iter, &sub);

          while (dbus_message_iter_get_arg_type (&sub))
            {
              const gchar *string;
              dbus_message_iter_get_basic (&sub, &string);
              g_variant_builder_add (&builder, "s", string);
              dbus_message_iter_next (&sub);
            }

          g_variant_builder_close (&builder);
        }
      dbus_message_iter_next (&iter);
    }

  return g_variant_ref_sink (g_variant_builder_end (&builder));
}

static GVariant *
dconf_libdbus_1_interpret_result (DBusMessage         *result,
                                  const GVariantType  *expected_type,
                                  GError             **error)
{
  GVariant *reply;

  if (dbus_message_get_type (result) == DBUS_MESSAGE_TYPE_ERROR)
    {
      const gchar *errstr = "(no message)";

      dbus_message_get_args (result, NULL, DBUS_TYPE_STRING, &errstr, DBUS_TYPE_INVALID);
      g_set_error (error, DCONF_LIBDBUS_1_ERROR, DCONF_LIBDBUS_1_ERROR_FAILED,
                   "%s: %s", dbus_message_get_error_name (result), errstr);
      return NULL;
    }

  reply = dconf_libdbus_1_get_message_body (result, error);

  if (reply && expected_type && !g_variant_is_of_type (reply, expected_type))
    {
      gchar *expected_string;

      expected_string = g_variant_type_dup_string (expected_type);
      g_set_error (error, DCONF_LIBDBUS_1_ERROR, DCONF_LIBDBUS_1_ERROR_FAILED,
                   "received reply '%s' is not of the expected type %s",
                   g_variant_get_type_string (reply), expected_string);
      g_free (expected_string);

      g_variant_unref (reply);
      reply = NULL;
    }

  return reply;
}

static void
dconf_libdbus_1_method_call_done (DBusPendingCall *pending,
                                  gpointer         user_data)
{
  DConfEngineCallHandle *handle = user_data;
  const GVariantType *expected_type;
  DBusMessage *message;
  GError *error = NULL;
  GVariant *reply;

  if (pending == NULL)
    return;

  message = dbus_pending_call_steal_reply (pending);
  dbus_pending_call_unref (pending);

  expected_type = dconf_engine_call_handle_get_expected_type (handle);
  reply = dconf_libdbus_1_interpret_result (message, expected_type, &error);
  dbus_message_unref (message);

  dconf_engine_call_handle_reply (handle, reply, error);

  if (reply)
    g_variant_unref (reply);
  if (error)
    g_error_free (error);
}

gboolean
dconf_engine_dbus_call_async_func (GBusType                bus_type,
                                   const gchar            *bus_name,
                                   const gchar            *object_path,
                                   const gchar            *interface_name,
                                   const gchar            *method_name,
                                   GVariant               *parameters,
                                   DConfEngineCallHandle  *handle,
                                   GError                **error)
{
  DBusConnection *connection;
  DBusPendingCall *pending;
  DBusMessage *message;

  g_assert_cmpint (bus_type, <, G_N_ELEMENTS (dconf_libdbus_1_buses));
  connection = dconf_libdbus_1_buses[bus_type];
  g_assert (connection != NULL);

  message = dconf_libdbus_1_new_method_call (bus_name, object_path, interface_name, method_name, parameters);
  dbus_connection_send_with_reply (connection, message, &pending, -1);
  dbus_pending_call_set_notify (pending, dconf_libdbus_1_method_call_done, handle, NULL);
  dbus_message_unref (message);

  return TRUE;
}

static void
dconf_libdbus_1_convert_error (DBusError  *dbus_error,
                               GError    **error)
{
  g_set_error (error, DCONF_LIBDBUS_1_ERROR, DCONF_LIBDBUS_1_ERROR_FAILED,
               "%s: %s", dbus_error->name, dbus_error->message);
}

GVariant *
dconf_engine_dbus_call_sync_func (GBusType             bus_type,
                                  const gchar         *bus_name,
                                  const gchar         *object_path,
                                  const gchar         *interface_name,
                                  const gchar         *method_name,
                                  GVariant            *parameters,
                                  const GVariantType  *expected_type,
                                  GError             **error)
{
  DBusConnection *connection;
  DBusMessage *message;
  DBusError dbus_error;
  DBusMessage *result;
  GVariant *reply;

  g_assert_cmpint (bus_type, <, G_N_ELEMENTS (dconf_libdbus_1_buses));
  connection = dconf_libdbus_1_buses[bus_type];
  g_assert (connection != NULL);

  dbus_error_init (&dbus_error);
  message = dconf_libdbus_1_new_method_call (bus_name, object_path, interface_name, method_name, parameters);
  result = dbus_connection_send_with_reply_and_block (connection, message, -1, &dbus_error);
  dbus_message_unref (message);

  if (result == NULL)
    {
      dconf_libdbus_1_convert_error (&dbus_error, error);
      dbus_error_free (&dbus_error);
      return NULL;
    }

  reply = dconf_libdbus_1_interpret_result (result, expected_type, error);
  dbus_message_unref (result);

  return reply;
}

static DBusHandlerResult
dconf_libdbus_1_filter (DBusConnection *connection,
                        DBusMessage    *message,
                        gpointer        user_data)
{
  GBusType bus_type = GPOINTER_TO_INT (user_data);

  if (dbus_message_get_type (message) == DBUS_MESSAGE_TYPE_SIGNAL)
    {
      const gchar *interface;

      interface = dbus_message_get_interface (message);

      if (interface && g_str_equal (interface, "ca.desrt.dconf.Writer"))
        {
          GVariant *parameters;

          parameters = dconf_libdbus_1_get_message_body (message, NULL);

          if (parameters != NULL)
            {
              dconf_engine_handle_dbus_signal (bus_type,
                                               dbus_message_get_sender (message),
                                               dbus_message_get_path (message),
                                               dbus_message_get_member (message),
                                               parameters);
              g_variant_unref (parameters);
            }
        }
    }

  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

void
dconf_libdbus_1_provide_bus (GBusType        bus_type,
                             DBusConnection *connection)
{
  g_assert_cmpint (bus_type, <, G_N_ELEMENTS (dconf_libdbus_1_buses));

  if (!dconf_libdbus_1_buses[bus_type])
    {
      dconf_libdbus_1_buses[bus_type] = dbus_connection_ref (connection);
      dbus_connection_add_filter (connection, dconf_libdbus_1_filter, GINT_TO_POINTER (bus_type), NULL);
    }
}

#ifndef PIC
static gboolean
dconf_libdbus_1_check_connection (gpointer user_data)
{
  DBusConnection *connection = user_data;

  dbus_connection_read_write (connection, 0);
  dbus_connection_dispatch (connection);

  return G_SOURCE_CONTINUE;
}

void
dconf_engine_dbus_init_for_testing (void)
{
  DBusConnection *session;
  DBusConnection *system;

  dconf_libdbus_1_provide_bus (G_BUS_TYPE_SESSION, session = dbus_bus_get (DBUS_BUS_SESSION, NULL));
  dconf_libdbus_1_provide_bus (G_BUS_TYPE_SYSTEM, system = dbus_bus_get (DBUS_BUS_SYSTEM, NULL));

  /* "mainloop integration" */
  g_timeout_add (1, dconf_libdbus_1_check_connection, session);
  g_timeout_add (1, dconf_libdbus_1_check_connection, system);
}
#endif
