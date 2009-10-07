/*
 * Copyright © 2007, 2008  Ryan Lortie
 * Copyright © 2009 Codethink Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 2.1
 * of the licence, or (at your option) any later version.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#include <dbus/dbus.h>
#include <string.h>
#include <dconf.h>
#include <stdio.h>
#include <glib.h>

static gint32 dconf_dbus_connection_slot = -1;

/* alexl code */
static void _g_dbus_connection_integrate_with_main (DBusConnection *);

static char dconf_dbus_service_introspection_blob[] =
"<?xml version='1.0' encoding='ascii'?>\n"
"\n"
"<!DOCTYPE node PUBLIC '-//freedesktop//DTD D-BUS Object Introspection 1.0//EN'\n"
"  'http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd'>\n"
"\n"
"<node>\n"
"  <interface name='org.freedesktop.DBus.Introspectable'>\n"
"    <method name='Introspect'>\n"
"      <arg name='data' direction='out' type='s'/>\n"
"    </method>\n"
"  </interface>\n"
"  <interface name='ca.desrt.dconf.Service'>\n"
"    <method name='Get'>\n"
"      <arg name='key' direction='in' type='s'/>\n"
"      <arg name='value' direction='out' type='av'/>\n"
"    </method>\n"
"    <method name='GetLocked'>\n"
"      <arg name='key_or_path' direction='in' type='s'/>\n"
"      <arg name='locked' direction='out' type='b'/>\n"
"    </method>\n"
"    <method name='GetWritable'>\n"
"      <arg name='key_or_path' direction='in' type='s'/>\n"
"      <arg name='writable' direction='out' type='b'/>\n"
"    </method>\n"
"    <method name='List'>\n"
"      <arg name='path' direction='in' type='s'/>\n"
"      <arg name='items' direction='out' type='as'/>\n"
"    </method>\n"
"    <method name='Merge'>\n"
"      <arg name='prefix' direction='in' type='s'/>\n"
"      <arg name='items' direction='in' type='a(sv)'/>\n"
"      <arg name='event_id' direction='out' type='s'/>\n"
"    </method>\n"
"    <method name='Reset'>\n"
"      <arg name='key_or_path' direction='in' type='s'/>\n"
"      <arg name='event_id' direction='out' type='s'/>\n"
"    </method>\n"
"    <method name='Set'>\n"
"      <arg name='key' direction='in' type='s'/>\n"
"      <arg name='value' direction='in' type='v'/>\n"
"      <arg name='event_id' direction='out' type='s'/>\n"
"    </method>\n"
"    <method name='SetLocked'>\n"
"      <arg name='key_or_path' direction='in' type='s'/>\n"
"      <arg name='locked' direction='in' type='b'/>\n"
"    </method>\n"
"    <signal name='Notify'>\n"
"      <arg name='prefix' type='s'/>\n"
"      <arg name='items' type='as'/>\n"
"      <arg name='event_id' type='s'/>\n"
"    </signal>\n"
"  </interface>\n"
"</node>\n"
;

static void
dconf_dbus_from_gv (DBusMessageIter *iter,
                    GVariant        *value)
{
  switch (g_variant_get_type_class (value))
    {
     case G_VARIANT_TYPE_CLASS_BOOLEAN:
      {
        dbus_bool_t v = g_variant_get_boolean (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_BOOLEAN, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_BYTE:
      {
        guint8 v = g_variant_get_byte (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_BYTE, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_INT16:
      {
        gint16 v = g_variant_get_int16 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_INT16, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_UINT16:
      {
        guint16 v = g_variant_get_uint16 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_UINT16, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_INT32:
      {
        gint32 v = g_variant_get_int32 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_INT32, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_UINT32:
      {
        guint32 v = g_variant_get_uint32 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_UINT32, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_INT64:
      {
        gint64 v = g_variant_get_int64 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_INT64, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_UINT64:
      {
        guint64 v = g_variant_get_uint64 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_UINT64, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_DOUBLE:
      {
        gdouble v = g_variant_get_double (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_DOUBLE, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_STRING:
      {
        const gchar *v = g_variant_get_string (value, NULL);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_STRING, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_OBJECT_PATH:
      {
        const gchar *v = g_variant_get_string (value, NULL);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_OBJECT_PATH, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_SIGNATURE:
      {
        const gchar *v = g_variant_get_string (value, NULL);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_SIGNATURE, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_VARIANT:
      {
        DBusMessageIter sub;
        GVariant *child;

        child = g_variant_get_child_value (value, 0);
        dbus_message_iter_open_container (iter, DBUS_TYPE_VARIANT,
                                          g_variant_get_type_string (child),
                                          &sub);
        dconf_dbus_from_gv (iter, child);
        dbus_message_iter_close_container (iter, &sub);
        g_variant_unref (child);
        break;
      }

     case G_VARIANT_TYPE_CLASS_MAYBE:
      g_error ("DBus does not (yet) support maybe types.");

     case G_VARIANT_TYPE_CLASS_ARRAY:
      {
        DBusMessageIter dbus_iter;
        const gchar *type_string;
        GVariantIter gv_iter;
        GVariant *item;

        type_string = g_variant_get_type_string (value);
        type_string++; /* skip the 'a' */

        dbus_message_iter_open_container (iter, DBUS_TYPE_ARRAY,
                                          type_string, &dbus_iter);
        g_variant_iter_init (&gv_iter, value);

        while ((item = g_variant_iter_next_value (&gv_iter)))
          dconf_dbus_from_gv (&dbus_iter, item);

        dbus_message_iter_close_container (iter, &dbus_iter);
        break;
      }

     case G_VARIANT_TYPE_CLASS_TUPLE:
      {
        DBusMessageIter dbus_iter;
        GVariantIter gv_iter;
        GVariant *item;

        dbus_message_iter_open_container (iter, DBUS_TYPE_STRUCT,
                                          NULL, &dbus_iter);
        g_variant_iter_init (&gv_iter, value);

        while ((item = g_variant_iter_next_value (&gv_iter)))
          dconf_dbus_from_gv (&dbus_iter, item);

        dbus_message_iter_close_container (iter, &dbus_iter);
        break;
      }

     case G_VARIANT_TYPE_CLASS_DICT_ENTRY:
      {
        DBusMessageIter dbus_iter;
        GVariant *key, *val;

        dbus_message_iter_open_container (iter, DBUS_TYPE_DICT_ENTRY,
                                          NULL, &dbus_iter);
        key = g_variant_get_child_value (value, 0);
        dconf_dbus_from_gv (&dbus_iter, key);
        g_variant_unref (key);

        val = g_variant_get_child_value (value, 1);
        dconf_dbus_from_gv (&dbus_iter, val);
        g_variant_unref (val);

        dbus_message_iter_close_container (iter, &dbus_iter);
        break;
      }

     default:
      g_assert_not_reached ();
    }
}

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
        gchar *type;

        dbus_message_iter_recurse (iter, &sub);
        class = dbus_message_iter_get_arg_type (iter);
        type = dbus_message_iter_get_signature (iter);
        builder = g_variant_builder_new (class, G_VARIANT_TYPE (type));
        g_free (type);

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

static void
dconf_dbus_variant_from_gv (DBusMessageIter *iter,
                            GVariant        *value)
{
  DBusMessageIter sub;

  dbus_message_iter_open_container (iter, DBUS_TYPE_VARIANT,
                                    g_variant_get_type_string (value),
                                    &sub);
  dconf_dbus_from_gv (&sub, value);
  dbus_message_iter_close_container (iter, &sub);
}

static gboolean
dconf_dbus_service_is_call (DBusMessage *message,
                            const gchar *method,
                            const gchar *signature)
{
  return dbus_message_is_method_call (message,
                                      "ca.desrt.dconf.Service",
                                      method) &&
         dbus_message_has_signature (message, signature);
}

static void
dconf_dbus_service_event_ready (DConfAsyncResult *result,
                                gpointer          user_data)
{
  DBusMessage *message = user_data;
  DBusConnection *connection;
  GError *error = NULL;
  DBusMessage *reply;
  gchar *event_id;

  /* NOTE: evil.
   * takes advantage of the undocumented fact that dconf_*_finish() are
   * all the same in terms of implementation
   */
  if (dconf_set_finish (result, &event_id, &error))
    {
      reply = dbus_message_new_method_return (message);
      dbus_message_append_args (reply,
                                DBUS_TYPE_STRING, &event_id,
                                DBUS_TYPE_INVALID);
    }
  else
    {
      reply = dbus_message_new_error (message,
                                      "ca.desrt.dconf.Service.Error",
                                      error->message);
      g_error_free (error);
    }

  connection = dbus_message_get_data (message, dconf_dbus_connection_slot);
  dbus_connection_send (connection, reply, NULL);
  dbus_message_unref (message);
  dbus_message_unref (reply);
}

static void
dconf_dbus_service_nonevent_ready (DConfAsyncResult *result,
                                   gpointer          user_data)
{
  DBusMessage *message = user_data;
  DBusConnection *connection;
  GError *error = NULL;
  DBusMessage *reply;

  if (dconf_set_locked_finish (result, &error))
    {
      reply = dbus_message_new_method_return (message);
    }
  else
    {
      reply = dbus_message_new_error (message,
                                      "ca.desrt.dconf.Service.Error",
                                      error->message);
      g_error_free (error);
    }

  connection = dbus_message_get_data (message, dconf_dbus_connection_slot);
  dbus_connection_send (connection, reply, NULL);
  dbus_message_unref (message);
  dbus_message_unref (reply);
}

static DBusHandlerResult
dconf_dbus_service_filter (DBusConnection *connection,
                           DBusMessage    *message,
                           gpointer        user_data)
{
  gboolean w;

  dbus_message_set_data (message, dconf_dbus_connection_slot,
                         connection, NULL);

  if (dbus_message_has_path (message, "/"))
    {
      if (dbus_message_is_method_call (message,
                                       "org.freedesktop.DBus.Introspectable",
                                       "Introspect") &&
          dbus_message_has_signature (message, ""))
        {
          const gchar *tmp = dconf_dbus_service_introspection_blob;
          DBusMessage *reply;

          reply = dbus_message_new_method_return (message);

          dbus_message_append_args (reply,
                                    DBUS_TYPE_STRING, &tmp,
                                    DBUS_TYPE_INVALID);
          dbus_connection_send (connection, reply, NULL);
          dbus_message_unref (reply);

          return DBUS_HANDLER_RESULT_HANDLED;
        }

      if (dconf_dbus_service_is_call (message, "Get", "s"))
        {
          DBusMessageIter iter, array;
          DBusMessage *reply;
          const gchar *key;
          GVariant *value;

          dbus_message_get_args (message, NULL,
                                 DBUS_TYPE_STRING, &key,
                                 DBUS_TYPE_INVALID);

          if (!dconf_is_key (key))
            {
              reply = dbus_message_new_error (message,
                                              "ca.desrt.dconf.Service.Error",
                                              "invalid key");

              dbus_connection_send (connection, reply, NULL);
              dbus_message_unref (reply);

              return DBUS_HANDLER_RESULT_HANDLED;
            }

          value = dconf_get (key);

          reply = dbus_message_new_method_return (message);
          dbus_message_iter_init_append (reply, &iter);
          dbus_message_iter_open_container (&iter,
                                            DBUS_TYPE_ARRAY, "v",
                                            &array);
          if (value != NULL)
            {
              dconf_dbus_variant_from_gv (&array, value);
              g_variant_unref (value);
            }

          dbus_message_iter_close_container (&iter, &array);

          dbus_connection_send (connection, reply, NULL);
          dbus_message_unref (reply);

          return DBUS_HANDLER_RESULT_HANDLED;
        }

      if ((w = dconf_dbus_service_is_call (message, "GetWritable", "s")) ||
          dconf_dbus_service_is_call (message, "GetLocked", "s"))
        {
          DBusMessageIter iter;
          DBusMessage *reply;
          const gchar *path;
          dbus_bool_t value;

          dbus_message_get_args (message, NULL,
                                 DBUS_TYPE_STRING, &path,
                                 DBUS_TYPE_INVALID);

          if (!dconf_is_path (path) && !dconf_is_key (path))
            {
              reply = dbus_message_new_error (message,
                                              "ca.desrt.dconf.Service.Error",
                                              "invalid key/path");

              dbus_connection_send (connection, reply, NULL);
              dbus_message_unref (reply);

              return DBUS_HANDLER_RESULT_HANDLED;
            }

          if (w)
            value = dconf_get_writable (path);
          else
            value = dconf_get_locked (path);

          reply = dbus_message_new_method_return (message);
          dbus_message_iter_init_append (reply, &iter);
          dbus_message_iter_append_basic (&iter, DBUS_TYPE_BOOLEAN, &value);

          dbus_connection_send (connection, reply, NULL);
          dbus_message_unref (reply);

          return DBUS_HANDLER_RESULT_HANDLED;
        }

      if (dconf_dbus_service_is_call (message, "List", "s"))
        {
          DBusMessageIter iter, array;
          DBusMessage *reply;
          const gchar *path;
          gchar **value;
          gint i;

          dbus_message_get_args (message, NULL,
                                 DBUS_TYPE_STRING, &path,
                                 DBUS_TYPE_INVALID);

          if (!dconf_is_path (path))
            {
              reply = dbus_message_new_error (message,
                                              "ca.desrt.dconf.Service.Error",
                                              "invalid path");

              dbus_connection_send (connection, reply, NULL);
              dbus_message_unref (reply);

              return DBUS_HANDLER_RESULT_HANDLED;
            }

          value = dconf_list (path, NULL);

          reply = dbus_message_new_method_return (message);
          dbus_message_iter_init_append (reply, &iter);
          dbus_message_iter_open_container (&iter,
                                            DBUS_TYPE_ARRAY, "s",
                                            &array);

          for (i = 0; value[i]; i++)
            dbus_message_iter_append_basic (&array,
                                            DBUS_TYPE_STRING,
                                            value + i);

          dbus_message_iter_close_container (&iter, &array);

          dbus_connection_send (connection, reply, NULL);
          dbus_message_unref (reply);
          g_strfreev (value);

          return DBUS_HANDLER_RESULT_HANDLED;
        }

      if (dconf_dbus_service_is_call (message, "Set", "sv"))
        {
          DBusMessageIter iter;
          DBusMessage *reply;
          const gchar *key;
          GVariant *value;

          dbus_message_iter_init (message, &iter);
          dbus_message_iter_get_basic (&iter, &key);

          if (!dconf_is_key (key))
            {
              reply = dbus_message_new_error (message,
                                              "ca.desrt.dconf.Service.Error",
                                              "invalid key");

              dbus_connection_send (connection, reply, NULL);
              dbus_message_unref (reply);

              return DBUS_HANDLER_RESULT_HANDLED;
            }

          dbus_message_iter_next (&iter);
          value = dconf_dbus_variant_to_gv (&iter);

          dconf_set_async (key, value,
                           dconf_dbus_service_event_ready,
                           dbus_message_ref (message));

          return DBUS_HANDLER_RESULT_HANDLED;
        }

      if (dconf_dbus_service_is_call (message, "Reset", "s"))
        {
          DBusMessage *reply;
          const gchar *key;

          dbus_message_get_args (message, NULL,
                                 DBUS_TYPE_STRING, &key,
                                 DBUS_TYPE_INVALID);

          if (!dconf_is_key (key) || !dconf_is_path (key))
            {
              reply = dbus_message_new_error (message,
                                              "ca.desrt.dconf.Service.Error",
                                              "invalid key/path");

              dbus_connection_send (connection, reply, NULL);
              dbus_message_unref (reply);

              return DBUS_HANDLER_RESULT_HANDLED;
            }

          dconf_reset_async (key,
                             dconf_dbus_service_event_ready,
                             dbus_message_ref (message));

          return DBUS_HANDLER_RESULT_HANDLED;
        }

      if (dconf_dbus_service_is_call (message, "Merge", "sa(sv)"))
        {
          DBusMessageIter iter, array;
          const gchar *prefix;
          DBusMessage *reply;
          GTree *tree;

          dbus_message_iter_init (message, &iter);
          dbus_message_iter_get_basic (&iter, &prefix);
          dbus_message_iter_next (&iter);
          dbus_message_iter_recurse (&iter, &array);

          /* XXX do more thorough check */
          if (!dconf_is_key (prefix) && !dconf_is_path (prefix))
            {
              reply = dbus_message_new_error (message,
                                              "ca.desrt.dconf.Service.Error",
                                              "invalid arguments");

              dbus_connection_send (connection, reply, NULL);
              dbus_message_unref (reply);

              return DBUS_HANDLER_RESULT_HANDLED;
            }

          tree = g_tree_new_full ((GCompareDataFunc) strcmp, NULL,
                                  g_free, (GDestroyNotify) g_variant_unref);

          while (dbus_message_iter_get_arg_type (&array))
            {
              DBusMessageIter tuple;
              const gchar *name;
              GVariant *value;

              dbus_message_iter_recurse (&array, &tuple);
              dbus_message_iter_get_basic (&tuple, &name);
              dbus_message_iter_next (&tuple);
              value = dconf_dbus_variant_to_gv (&tuple);

              /* XXX check 'name' for validity */
              g_tree_insert (tree, g_strdup (name), value);

              dbus_message_iter_next (&array);
            }

          dconf_merge_async (prefix, tree,
                             dconf_dbus_service_event_ready,
                             dbus_message_ref (message));
          g_tree_unref (tree);

          return DBUS_HANDLER_RESULT_HANDLED;
        }

      if (dconf_dbus_service_is_call (message, "SetLocked", "sb"))
        {
          DBusMessage *reply;
          dbus_bool_t locked;
          const gchar *key;

          dbus_message_get_args (message, NULL,
                                 DBUS_TYPE_STRING, &key,
                                 DBUS_TYPE_BOOLEAN, &locked,
                                 DBUS_TYPE_INVALID);

          if (!dconf_is_key (key) || !dconf_is_path (key))
            {
              reply = dbus_message_new_error (message,
                                              "ca.desrt.dconf.Service.Error",
                                              "invalid key/path");

              dbus_connection_send (connection, reply, NULL);
              dbus_message_unref (reply);

              return DBUS_HANDLER_RESULT_HANDLED;
            }

          dconf_set_locked_async (key, locked,
                                  dconf_dbus_service_nonevent_ready,
                                  dbus_message_ref (message));

          return DBUS_HANDLER_RESULT_HANDLED;
        }
    }

  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

int
main (void)
{
  DBusError d_error = {  };
  DBusConnection *bus;

  dbus_message_allocate_data_slot (&dconf_dbus_connection_slot);
  bus = dbus_bus_get (DBUS_BUS_SESSION, &d_error);

  if (bus == NULL)
    {
      fprintf (stderr, "%s: %s\n", d_error.name, d_error.message);
      return 1;
    }

  if (dbus_bus_request_name (bus, "ca.desrt.dconf.Service", 0, &d_error) !=
      DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER)
    {
      fprintf (stderr,
               "fatal: failed to acquire bus name ca.desrt.dconf.Service\n");

      return 1;
    }

  dbus_connection_add_filter (bus, dconf_dbus_service_filter, NULL, NULL);
  _g_dbus_connection_integrate_with_main (bus);

  {
    GMainLoop *loop;

    loop = g_main_loop_new (NULL, FALSE);
    g_main_loop_run (loop);
    g_main_loop_unref (loop);
  }

  return 0;
}

/* ------------------------------------------------------------------------ */
/* all code past this point is for mainloop integration.
 *
 * this code was lifted from common/gdbusutils.c in gvfs.
 * it has been slightly modified to remove its dependence on libgio.
 *
 * Copyright (C) 2006-2007 Red Hat, Inc.
 * Author: Alexander Larsson <alexl@redhat.com>
 * Modified: Ryan Lortie <desrt@desrt.ca>
 */

typedef gboolean (*GFDSourceFunc) (gpointer data,
                                   GIOCondition condition,
                                   int fd);

static void
_g_dbus_oom (void)
{
  g_error ("DBus failed with out of memory error");
}

/*************************************************************************
 *             Helper fd source                                          *
 ************************************************************************/

typedef struct
{
  GSource source;
  GPollFD pollfd;
} FDSource;

static gboolean
fd_source_prepare (GSource  *source,
		   gint     *timeout)
{
  *timeout = -1;

  return FALSE;
}

static gboolean
fd_source_check (GSource  *source)
{
  FDSource *fd_source = (FDSource *)source;

  return fd_source->pollfd.revents != 0;
}

static gboolean
fd_source_dispatch (GSource     *source,
		    GSourceFunc  callback,
		    gpointer     user_data)

{
  GFDSourceFunc func = (GFDSourceFunc)callback;
  FDSource *fd_source = (FDSource *)source;

  g_assert (func != NULL);

  return (*func) (user_data, fd_source->pollfd.revents, fd_source->pollfd.fd);
}

static GSourceFuncs fd_source_funcs = {
  fd_source_prepare,
  fd_source_check,
  fd_source_dispatch,
  NULL
};

/* Two __ to avoid conflict with gio version */
static GSource *
__g_fd_source_new (int fd,
		   gushort events)
{
  GSource *source;
  FDSource *fd_source;

  source = g_source_new (&fd_source_funcs, sizeof (FDSource));
  fd_source = (FDSource *)source;

  fd_source->pollfd.fd = fd;
  fd_source->pollfd.events = events;
  g_source_add_poll (source, &fd_source->pollfd);

  return source;
}

/*************************************************************************
 *                                                                       *
 *      dbus mainloop integration for async ops                          *
 *                                                                       *
 *************************************************************************/

static gint32 main_integration_data_slot = -1;
static GOnce once_init_main_integration = G_ONCE_INIT;

/**
 * A GSource subclass for dispatching DBusConnection messages.
 * We need this on top of the IO handlers, because sometimes
 * there are messages to dispatch queued up but no IO pending.
 *
 * The source is owned by the connection (and the main context
 * while that is alive)
 */
typedef struct
{
  GSource source;

  DBusConnection *connection;
  GSList *ios;
  GSList *timeouts;
} DBusSource;

typedef struct
{
  DBusSource *dbus_source;
  GSource *source;
  DBusWatch *watch;
} IOHandler;

typedef struct
{
  DBusSource *dbus_source;
  GSource *source;
  DBusTimeout *timeout;
} TimeoutHandler;

static gpointer
main_integration_init (gpointer arg)
{
  if (!dbus_connection_allocate_data_slot (&main_integration_data_slot))
    g_error ("Unable to allocate data slot");

  return NULL;
}

static gboolean
dbus_source_prepare (GSource *source,
		     gint    *timeout)
{
  DBusConnection *connection = ((DBusSource *)source)->connection;

  *timeout = -1;

  return (dbus_connection_get_dispatch_status (connection) == DBUS_DISPATCH_DATA_REMAINS);
}

static gboolean
dbus_source_check (GSource *source)
{
  return FALSE;
}

static gboolean
dbus_source_dispatch (GSource     *source,
		      GSourceFunc  callback,
		      gpointer     user_data)
{
  DBusConnection *connection = ((DBusSource *)source)->connection;

  dbus_connection_ref (connection);

  /* Only dispatch once - we don't want to starve other GSource */
  dbus_connection_dispatch (connection);

  dbus_connection_unref (connection);

  return TRUE;
}

static gboolean
io_handler_dispatch (gpointer data,
                     GIOCondition condition,
                     int fd)
{
  IOHandler *handler = data;
  guint dbus_condition = 0;
  DBusConnection *connection;

  connection = handler->dbus_source->connection;

  if (connection)
    dbus_connection_ref (connection);

  if (condition & G_IO_IN)
    dbus_condition |= DBUS_WATCH_READABLE;
  if (condition & G_IO_OUT)
    dbus_condition |= DBUS_WATCH_WRITABLE;
  if (condition & G_IO_ERR)
    dbus_condition |= DBUS_WATCH_ERROR;
  if (condition & G_IO_HUP)
    dbus_condition |= DBUS_WATCH_HANGUP;

  /* Note that we don't touch the handler after this, because
   * dbus may have disabled the watch and thus killed the
   * handler.
   */
  dbus_watch_handle (handler->watch, dbus_condition);
  handler = NULL;

  if (connection)
    dbus_connection_unref (connection);

  return TRUE;
}

static void
io_handler_free (IOHandler *handler)
{
  DBusSource *dbus_source;

  dbus_source = handler->dbus_source;
  dbus_source->ios = g_slist_remove (dbus_source->ios, handler);

  g_source_destroy (handler->source);
  g_source_unref (handler->source);
  g_free (handler);
}

static void
dbus_source_add_watch (DBusSource *dbus_source,
		       DBusWatch *watch)
{
  guint flags;
  GIOCondition condition;
  IOHandler *handler;
  int fd;

  if (!dbus_watch_get_enabled (watch))
    return;

  g_assert (dbus_watch_get_data (watch) == NULL);

  flags = dbus_watch_get_flags (watch);

  condition = G_IO_ERR | G_IO_HUP;
  if (flags & DBUS_WATCH_READABLE)
    condition |= G_IO_IN;
  if (flags & DBUS_WATCH_WRITABLE)
    condition |= G_IO_OUT;

  handler = g_new0 (IOHandler, 1);
  handler->dbus_source = dbus_source;
  handler->watch = watch;

#if (DBUS_MAJOR_VERSION == 1 && DBUS_MINOR_VERSION == 1 && DBUS_MICRO_VERSION >= 1) || (DBUS_MAJOR_VERSION == 1 && DBUS_MINOR_VERSION > 1) || (DBUS_MAJOR_VERSION > 1)
  fd = dbus_watch_get_unix_fd (watch);
#else
  fd = dbus_watch_get_fd (watch);
#endif

  handler->source = __g_fd_source_new (fd, condition);
  g_source_set_callback (handler->source,
			 (GSourceFunc) io_handler_dispatch, handler,
                         NULL);
  g_source_attach (handler->source, NULL);

  dbus_source->ios = g_slist_prepend (dbus_source->ios, handler);
  dbus_watch_set_data (watch, handler,
		       (DBusFreeFunction)io_handler_free);
}

static void
dbus_source_remove_watch (DBusSource *dbus_source,
			  DBusWatch *watch)
{
  dbus_watch_set_data (watch, NULL, NULL);
}

static void
timeout_handler_free (TimeoutHandler *handler)
{
  DBusSource *dbus_source;

  dbus_source = handler->dbus_source;
  dbus_source->timeouts = g_slist_remove (dbus_source->timeouts, handler);

  g_source_destroy (handler->source);
  g_source_unref (handler->source);
  g_free (handler);
}

static gboolean
timeout_handler_dispatch (gpointer      data)
{
  TimeoutHandler *handler = data;

  dbus_timeout_handle (handler->timeout);

  return TRUE;
}

static void
dbus_source_add_timeout (DBusSource *dbus_source,
			 DBusTimeout *timeout)
{
  TimeoutHandler *handler;

  if (!dbus_timeout_get_enabled (timeout))
    return;

  g_assert (dbus_timeout_get_data (timeout) == NULL);

  handler = g_new0 (TimeoutHandler, 1);
  handler->dbus_source = dbus_source;
  handler->timeout = timeout;

  handler->source = g_timeout_source_new (dbus_timeout_get_interval (timeout));
  g_source_set_callback (handler->source,
			 timeout_handler_dispatch, handler,
                         NULL);
  g_source_attach (handler->source, NULL);

  /* handler->source is owned by the context here */
  dbus_source->timeouts = g_slist_prepend (dbus_source->timeouts, handler);

  dbus_timeout_set_data (timeout, handler,
			 (DBusFreeFunction)timeout_handler_free);
}

static void
dbus_source_remove_timeout (DBusSource *source,
			    DBusTimeout *timeout)
{
  dbus_timeout_set_data (timeout, NULL, NULL);
}

static dbus_bool_t
add_watch (DBusWatch *watch,
	   gpointer   data)
{
  DBusSource *dbus_source = data;

  dbus_source_add_watch (dbus_source, watch);

  return TRUE;
}

static void
remove_watch (DBusWatch *watch,
	      gpointer   data)
{
  DBusSource *dbus_source = data;

  dbus_source_remove_watch (dbus_source, watch);
}

static void
watch_toggled (DBusWatch *watch,
               void      *data)
{
  /* Because we just exit on OOM, enable/disable is
   * no different from add/remove */
  if (dbus_watch_get_enabled (watch))
    add_watch (watch, data);
  else
    remove_watch (watch, data);
}

static dbus_bool_t
add_timeout (DBusTimeout *timeout,
	     void        *data)
{
  DBusSource *source = data;

  if (!dbus_timeout_get_enabled (timeout))
    return TRUE;

  dbus_source_add_timeout (source, timeout);

  return TRUE;
}

static void
remove_timeout (DBusTimeout *timeout,
		void        *data)
{
  DBusSource *source = data;

  dbus_source_remove_timeout (source, timeout);
}

static void
timeout_toggled (DBusTimeout *timeout,
                 void        *data)
{
  /* Because we just exit on OOM, enable/disable is
   * no different from add/remove
   */
  if (dbus_timeout_get_enabled (timeout))
    add_timeout (timeout, data);
  else
    remove_timeout (timeout, data);
}

static void
wakeup_main (void *data)
{
  g_main_context_wakeup (NULL);
}

static const GSourceFuncs dbus_source_funcs = {
  dbus_source_prepare,
  dbus_source_check,
  dbus_source_dispatch
};

/* Called when the connection dies or when we're unintegrating from mainloop */
static void
dbus_source_free (DBusSource *dbus_source)
{
  while (dbus_source->ios)
    {
      IOHandler *handler = dbus_source->ios->data;

      dbus_watch_set_data (handler->watch, NULL, NULL);
    }

  while (dbus_source->timeouts)
    {
      TimeoutHandler *handler = dbus_source->timeouts->data;

      dbus_timeout_set_data (handler->timeout, NULL, NULL);
    }

  /* Remove from mainloop */
  g_source_destroy ((GSource *)dbus_source);

  g_source_unref ((GSource *)dbus_source);
}

static void
_g_dbus_connection_remove_from_main (DBusConnection *connection)
{
  g_once (&once_init_main_integration, main_integration_init, NULL);

  if (!dbus_connection_set_data (connection,
				 main_integration_data_slot,
				 NULL, NULL))
    _g_dbus_oom ();
}

static void
_g_dbus_connection_integrate_with_main (DBusConnection *connection)
{
  DBusSource *dbus_source;

  g_once (&once_init_main_integration, main_integration_init, NULL);

  g_assert (connection != NULL);

  _g_dbus_connection_remove_from_main (connection);

  dbus_source = (DBusSource *)
    g_source_new ((GSourceFuncs*)&dbus_source_funcs,
		  sizeof (DBusSource));

  dbus_source->connection = connection;

  if (!dbus_connection_set_watch_functions (connection,
                                            add_watch,
                                            remove_watch,
                                            watch_toggled,
                                            dbus_source, NULL))
    _g_dbus_oom ();

  if (!dbus_connection_set_timeout_functions (connection,
                                              add_timeout,
                                              remove_timeout,
                                              timeout_toggled,
                                              dbus_source, NULL))
    _g_dbus_oom ();

  dbus_connection_set_wakeup_main_function (connection,
					    wakeup_main,
					    dbus_source, NULL);

  /* Owned by both connection and mainloop (until destroy) */
  g_source_attach ((GSource *)dbus_source, NULL);

  if (!dbus_connection_set_data (connection,
				 main_integration_data_slot,
				 dbus_source, (DBusFreeFunction)dbus_source_free))
    _g_dbus_oom ();
}
