/*
 * Copyright © 2009 Codethink Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#include <dbus/dbus.h>
#include <string.h>
#include <stdio.h>
#include <glib.h>

#include "dconf-service.h"

typedef struct
{
  DConfService *service;

  DBusConnection *bus;
  DBusMessage *this;

  GSList *signals;
} DConfDBusService;

static GVariant *
dconf_dbus_to_gv (DBusMessageIter *iter)
{
  switch (dbus_message_iter_get_arg_type (iter))
    {
     case DBUS_TYPE_BOOLEAN:
      {
        dbus_bool_t value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_boolean (value);
      }

     case DBUS_TYPE_BYTE:
      {
        guchar value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_byte (value);
      }

     case DBUS_TYPE_INT16:
      {
        gint16 value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_int16 (value);
      }

     case DBUS_TYPE_UINT16:
      {
        guint16 value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_uint16 (value);
      }

     case DBUS_TYPE_INT32:
      {
        gint32 value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_int32 (value);
      }

     case DBUS_TYPE_UINT32:
      {
        guint32 value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_uint32 (value);
      }

     case DBUS_TYPE_INT64:
      {
        gint64 value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_int64 (value);
      }

     case DBUS_TYPE_UINT64:
      {
        guint64 value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_uint64 (value);
      }

     case DBUS_TYPE_DOUBLE:
      {
        gdouble value;
        dbus_message_iter_get_basic (iter, &value);
        return g_variant_new_double (value);
      }

     case DBUS_TYPE_STRING:
      {
       const gchar *value;
       dbus_message_iter_get_basic (iter, &value);
       return g_variant_new_string (value);
      }

     case DBUS_TYPE_OBJECT_PATH:
      {
       const gchar *value;
       dbus_message_iter_get_basic (iter, &value);
       return g_variant_new_object_path (value);
      }

     case DBUS_TYPE_SIGNATURE:
      {
       const gchar *value;
       dbus_message_iter_get_basic (iter, &value);
       return g_variant_new_signature (value);
      }

     case DBUS_TYPE_ARRAY:
     case DBUS_TYPE_VARIANT:
     case DBUS_TYPE_STRUCT:
     case DBUS_TYPE_DICT_ENTRY:
      {
        GVariantBuilder *builder;
        GVariantTypeClass class;
        DBusMessageIter sub;

        dbus_message_iter_recurse (iter, &sub);
        class = dbus_message_iter_get_arg_type (iter);
        builder = g_variant_builder_new (class, NULL);

        while (dbus_message_iter_get_arg_type (&sub))
          {
            g_variant_builder_add_value (builder, dconf_dbus_to_gv (&sub));
            dbus_message_iter_next (&sub);
          }

        return g_variant_builder_end (builder);
      }

     default:
      g_assert_not_reached ();
    }
}

static GVariant *
dconf_dbus_variant_to_gv (DBusMessageIter *iter)
{
  DBusMessageIter sub;

  g_assert (dbus_message_iter_get_arg_type (iter) == DBUS_TYPE_VARIANT);

  dbus_message_iter_recurse (iter, &sub);
  return g_variant_ref_sink (dconf_dbus_to_gv (&sub));
}

static gboolean
dconf_dbus_service_is_call (DConfDBusService *service,
                            const gchar      *method,
                            const gchar      *signature)
{
  return dbus_message_is_method_call (service->this,
                                      "ca.desrt.dconf", method) &&
         dbus_message_has_signature (service->this, signature);
}

static DBusMessage *
dconf_dbus_service_reply (DConfDBusService *service,
                          gboolean          success,
                          gint              sequence,
                          GError           *error)
{
  DBusMessage *reply;

  g_assert (success == (error == NULL));

  if (success)
    {
      reply = dbus_message_new_method_return (service->this);

      if (sequence >= 0)
        dbus_message_append_args (reply,
                                  DBUS_TYPE_UINT32, &sequence,
                                  DBUS_TYPE_INVALID);
    }
  else
    {
      reply = dbus_message_new_error (service->this,
                                      "ca.desrt.dconf.error",
                                      error->message);
      g_error_free (error);
    }

  return reply;
}

static void
dconf_dbus_service_notify (DConfDBusService  *service,
                           const gchar       *prefix,
                           const gchar      **items,
                           guint32            sequence)
{
  const gchar *my_items[] = { "", NULL };
  DBusMessageIter iter, array;
  DBusMessage *notify;

  notify = dbus_message_new_signal ("/user", "ca.desrt.dconf", "Notify");
  dbus_message_iter_init_append (notify, &iter);
  dbus_message_iter_append_basic (&iter, DBUS_TYPE_STRING, &prefix);
  dbus_message_iter_open_container (&iter, DBUS_TYPE_ARRAY, "s", &array);

  if (items == NULL)
    items = my_items;

  while (*items)
    dbus_message_iter_append_basic (&array, DBUS_TYPE_STRING, items++);

  dbus_message_iter_close_container (&iter, &array);
  dbus_message_iter_append_basic (&iter, DBUS_TYPE_UINT32, &sequence);

  service->signals = g_slist_prepend (service->signals, notify);
}

static DBusMessage *
dconf_dbus_service_handle_message (DConfDBusService *service)
{
  DBusMessageIter iter;

  dbus_message_iter_init (service->this, &iter);

  if (dconf_dbus_service_is_call (service, "Set", "sv"))
    {
      GError *error = NULL;
      guint32 sequence;
      const gchar *key;
      GVariant *value;
      gboolean status;

      dbus_message_iter_get_basic (&iter, &key);
      dbus_message_iter_next (&iter);
      value = dconf_dbus_variant_to_gv (&iter);
      dbus_message_iter_next (&iter);

      status = dconf_service_set (service->service,
                                  key, value, &sequence, &error);
      g_variant_unref (value);

      if (status == TRUE)
        dconf_dbus_service_notify (service, key, NULL, sequence);

      return dconf_dbus_service_reply (service, status, sequence, error);
    }

  if (dconf_dbus_service_is_call (service, "SetLocked", "sb"))
    {
      GError *error = NULL;
      dbus_bool_t locked;
      const gchar *key;
      gboolean status;

      dbus_message_iter_get_basic (&iter, &key);
      dbus_message_iter_next (&iter);
      dbus_message_iter_get_basic (&iter, &locked);
      dbus_message_iter_next (&iter);

      status = dconf_service_set_locked (service->service,
                                         key, locked, &error);

      return dconf_dbus_service_reply (service, status, -1, error);
    }

  return NULL;
}

static DBusHandlerResult
dconf_dbus_service_filter (DBusConnection *connection,
                           DBusMessage    *message,
                           gpointer        user_data)
{
  DConfDBusService *service = user_data;
  DBusMessage *reply;

  g_assert (connection == service->bus);

  if (dbus_message_has_path (message, "/user"))
    {
      service->this = message;
      reply = dconf_dbus_service_handle_message (service);
      service->this = NULL;

      if (reply)
        {
          dbus_connection_send (connection, reply, NULL);
          dbus_message_unref (reply);

          while (service->signals)
            {
              dbus_connection_send (connection, service->signals->data, NULL);
              dbus_message_unref (service->signals->data);
              service->signals = g_slist_delete_link (service->signals,
                                                      service->signals);
            }

          return DBUS_HANDLER_RESULT_HANDLED;
        }
    }

  g_assert (service->signals == NULL);

  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

int
main (int argc, char **argv)
{
  DConfDBusService service = { 0, };

  service.service = dconf_service_new ();
  service.bus = dbus_bus_get (DBUS_BUS_SESSION, NULL);
  dbus_bus_request_name (service.bus, "ca.desrt.dconf.user", 0, NULL);

  dbus_connection_add_filter (service.bus,
                              dconf_dbus_service_filter,
                              &service, NULL);

  while (dbus_connection_read_write_dispatch (service.bus, -1));

  return 0;
}
