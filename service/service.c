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

#include <gio/gio.h>
#include <string.h>
#include <stdio.h>

#include "dconf-rebuilder.h"

static const GDBusArgInfo name_arg = { -1, "name", "s" };
static const GDBusArgInfo names_arg = { -1, "names", "as" };
static const GDBusArgInfo serial_arg = { -1, "serial", "t" };
static const GDBusArgInfo locked_arg = { -1, "locked", "b" };
static const GDBusArgInfo value_arg = { -1, "value", "av" };
static const GDBusArgInfo values_arg = { -1, "values", "a(sav)" };

static const GDBusArgInfo *write_inargs[] = { &name_arg, &value_arg, NULL };
static const GDBusArgInfo *write_outargs[] = { &serial_arg, NULL };

static const GDBusArgInfo *merge_inargs[] = { &name_arg, &values_arg, NULL };
static const GDBusArgInfo *merge_outargs[] = { &serial_arg, NULL };

static const GDBusArgInfo *gsd_inargs[] = { NULL };
static const GDBusArgInfo *gsd_outargs[] = { &name_arg, NULL };

static const GDBusMethodInfo write_method = {
  -1, "Write",         (gpointer) write_inargs, (gpointer) write_outargs };
static const GDBusMethodInfo merge_method = {
  -1, "Merge",         (gpointer) merge_inargs, (gpointer) merge_outargs };
static const GDBusMethodInfo gsd_method = {
  -1, "GetSessionDir", (gpointer) gsd_inargs,   (gpointer) gsd_outargs };

static const GDBusMethodInfo *writer_methods[] = {
  &write_method, &merge_method, &gsd_method, NULL
};

static const GDBusInterfaceInfo writer_interface = {
  -1, "ca.desrt.dconf.Writer", (gpointer) writer_methods
};

typedef struct
{
  GMainLoop *loop;
  guint64 serial;
  gchar *path;
} DConfWriter;

static void
emit_notify_signal (GDBusConnection  *connection,
                    guint64           serial,
                    const gchar      *prefix,
                    const gchar     **keys,
                    guint             n_keys)
{
  GVariantBuilder builder;
  GVariant *items;
  gchar *path;

  g_variant_builder_init (&builder, G_VARIANT_TYPE ("as"));

  if (n_keys > 1)
    {
      const gchar *last_reset = NULL;
      gint last_reset_len;
      gint i;

      for (i = 0; i < n_keys; i++)
        {
          gint length = strlen (keys[i]);

          if (last_reset && length > last_reset_len &&
              memcmp (last_reset, keys[i], last_reset_len) == 0)
            continue;

          if (length == 0 || keys[i][length - 1] == '/')
            {
              last_reset_len = length;
              last_reset = keys[i];
            }
          else
            {
              if (last_reset != NULL)
                {
                  g_variant_builder_add (&builder, "s", last_reset);
                  last_reset = NULL;
                }

              g_variant_builder_add (&builder, "s", keys[i]);
            }
        }
    }

  items = g_variant_builder_end (&builder);

  if (g_variant_n_children (items) == 0)
    path = g_strconcat (prefix, keys[0], NULL);
  else
    path = g_strdup (prefix);

  g_dbus_connection_emit_signal (connection, NULL, "/",
                                 "ca.desrt.dconf.Writer", "Notify",
                                 g_variant_new ("(ts@as)",
                                                serial, path, items),
                                 NULL);
  g_free (path);
}

static GVariant *
unwrap_maybe (GVariant **ptr)
{
  GVariant *array, *child;

  array = *ptr;

  if (g_variant_n_children (array))
    child = g_variant_get_child_value (array, 0);
  else
    child = NULL;

  g_variant_unref (array);
  *ptr = child;
}

static void
method_call (GDBusConnection       *connection,
             const gchar           *sender,
             const gchar           *object_path,
             const gchar           *interface_name,
             const gchar           *method_name,
             GVariant              *parameters,
             GDBusMethodInvocation *invocation,
             gpointer               user_data)
{
  DConfWriter *writer = user_data;

  if (strcmp (method_name, "Write") == 0)
    {
      GError *error = NULL;
      GVariant *keyvalue;
      const gchar *key;
      gsize key_length;
      GVariant *value;
      guint64 serial;
      GVariant *none;

      g_variant_get (parameters, "(@s@av)", &keyvalue, &value);
      key = g_variant_get_string (keyvalue, &key_length);
      g_variant_unref (keyvalue);
      unwrap_maybe (&value);

      if (key[0] != '/' || strstr (key, "//"))
        {
          g_dbus_method_invocation_return_error (invocation, G_DBUS_ERROR,
                                                 G_DBUS_ERROR_INVALID_ARGS,
                                                 "invalid key: %s", key);
          if (value != NULL)
            g_variant_unref (value);

          return;
        }

      if (key[key_length - 1] == '/' && value != NULL)
        {
          g_dbus_method_invocation_return_error (invocation, G_DBUS_ERROR,
                                                 G_DBUS_ERROR_INVALID_ARGS,
                                                 "can not set value to path");
          g_variant_unref (value);
          return;
        }

      if (!dconf_rebuilder_rebuild (writer->path, "", &key,
                                    &value, 1, &error))
        {
          g_dbus_method_invocation_return_gerror (invocation, error);
          g_error_free (error);
          return;
        }

      serial = writer->serial++;
      g_dbus_method_invocation_return_value (invocation,
                                             g_variant_new ("(t)", serial));
      none = g_variant_new_array (G_VARIANT_TYPE_STRING, NULL, 0);
      g_dbus_connection_emit_signal (connection, NULL, "/",
                                     "ca.desrt.dconf.Writer", "Notify",
                                     g_variant_new ("(ts@as)",
                                                    serial, key, none),
                                     NULL);
    }
  else if (strcmp (method_name, "Merge"))
    {
      GError *error = NULL;
      const gchar *prefix;
      GVariantIter *iter;
      const gchar **keys;
      GVariant **values;
      guint64 serial;
      gsize length;
      gint i = 0;
      gint j;

      g_variant_get (parameters, "(&sa(sav))", &prefix, &iter);
      length = g_variant_iter_n_children (iter);

      keys = g_new (const gchar *, length);
      values = g_new (GVariant *, length);
      while (g_variant_iter_next (iter, "(&s@av)", &keys[i], &values[i]))
        {
          unwrap_maybe (&values[i]);

          if (keys[i][0] == '/' || strstr (keys[i], "//") ||
              (i > 0 && !(strcmp (keys[i - 1], keys[i]) < 0)))
            {
              g_dbus_method_invocation_return_error (invocation, G_DBUS_ERROR,
                                                     G_DBUS_ERROR_INVALID_ARGS,
                                                     "invalid key list");

              for (j = 0; j <= i; j++)
                if (values[j] != NULL)
                  g_variant_unref (values[j]);

              g_free (values);
              g_free (keys);

              return;
            }

          i++;
        }
      g_variant_iter_free (iter);
      keys[i] = NULL;

      if (!dconf_rebuilder_rebuild (writer->path, prefix, keys,
                                    values, i, &error))
        {
          g_dbus_method_invocation_return_gerror (invocation, error);
          g_error_free (error);
          return;
        }

      serial = writer->serial++;

      g_dbus_method_invocation_return_value (invocation,
                                             g_variant_new ("(t)", serial));
      emit_notify_signal (connection, serial, prefix, keys, i);

      for (j = 0; j < i; j++)
        if (values[j] != NULL)
          g_variant_unref (values[j]);

      g_free (values);
      g_free (keys);
    }
  else
    g_assert_not_reached ();
}

static void
bus_acquired (GDBusConnection *connection,
              const gchar     *name,
              gpointer         user_data)
{
  static const GDBusInterfaceVTable interface_vtable = { method_call };
  DConfWriter *writer = user_data;

  g_dbus_connection_register_object (connection, "/",
                                     &writer_interface, &interface_vtable,
                                     writer, NULL, NULL);
}

static void
name_acquired (GDBusConnection *connection,
               const gchar     *name,
               gpointer         user_data)
{
  DConfWriter *writer = user_data;

  writer->serial = time (NULL);
  writer->serial <<= 32;
}

static void
name_lost (GDBusConnection *connection,
           const gchar     *name,
           gpointer         user_data)
{
  DConfWriter *writer = user_data;

  if (writer->serial != 0)
    g_critical ("dbus signaled that we lost our "
                "name but it wrong wrong to do so");
  else
    g_critical ("unable to acquire name: '%s'", name);

  g_main_loop_quit (writer->loop);
}

int
main (void)
{
  DConfWriter writer = {  };

  g_type_init ();

  writer.loop = g_main_loop_new (NULL, FALSE);
  writer.path = g_build_filename (g_get_user_config_dir (), "dconf", NULL);

  g_bus_own_name (G_BUS_TYPE_SESSION, "ca.desrt.dconf", 0,
                  bus_acquired, name_acquired, name_lost, &writer, NULL);

  g_main_loop_run (writer.loop);

  return 0;
}
