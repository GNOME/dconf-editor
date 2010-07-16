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

#include "dconf-interfaces.h"
#include "dconf-writer.h"

static guint64 dconf_service_serial;

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

static void
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

      if (!dconf_writer_write (writer, key, value, &error))
        {
          g_dbus_method_invocation_return_gerror (invocation, error);
          g_error_free (error);
          return;
        }

      serial = dconf_service_serial++;
      g_dbus_method_invocation_return_value (invocation,
                                             g_variant_new ("(t)", serial));
      none = g_variant_new_array (G_VARIANT_TYPE_STRING, NULL, 0);
      g_dbus_connection_emit_signal (connection, NULL, "/",
                                     "ca.desrt.dconf.Writer", "Notify",
                                     g_variant_new ("(ts@as)",
                                                    serial, key, none),
                                     NULL);
    }
  else if (strcmp (method_name, "Merge") == 0)
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

      keys = g_new (const gchar *, length + 1);
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

      if (!dconf_writer_write_many (writer, prefix, keys, values, i, &error))
        {
          g_dbus_method_invocation_return_gerror (invocation, error);
          g_error_free (error);
          return;
        }

      serial = dconf_service_serial++;

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

static GVariant *
writer_info_get_property (GDBusConnection  *connection,
                          const gchar      *sender,
                          const gchar      *object_path,
                          const gchar      *interface_name,
                          const gchar      *property_name,
                          GError          **error,
                          gpointer          user_data)
{
  return g_variant_new_string (dconf_writer_get_shm_dir ());
}

static const GDBusInterfaceVTable *
subtree_dispatch (GDBusConnection *connection,
                  const gchar     *sender,
                  const gchar     *object_path,
                  const gchar     *interface_name,
                  const gchar     *node,
                  gpointer        *out_user_data,
                  gpointer         user_data)
{
  if (strcmp (interface_name, "ca.desrt.dconf.Writer") == 0)
    {
      static const GDBusInterfaceVTable vtable = {
        method_call, NULL, NULL
      };
      static GHashTable *writer_table;
      DConfWriter *writer;

      if (node == NULL)
        return NULL;

      if G_UNLIKELY (writer_table == NULL)
        writer_table = g_hash_table_new (g_str_hash, g_str_equal);

      writer = g_hash_table_lookup (writer_table, node);

      if G_UNLIKELY (writer == NULL)
        {
          writer = dconf_writer_new (node);
          g_hash_table_insert (writer_table, g_strdup (node), writer);
        }

      *out_user_data = writer;

      return &vtable;
    }

  else if (strcmp (interface_name, "ca.desrt.dconf.WriterInfo") == 0)
    {
      static const GDBusInterfaceVTable vtable = {
        NULL, writer_info_get_property, NULL
      };

      *out_user_data = NULL;
      return &vtable;
    }

  else
    return NULL;
}

static gchar **
subtree_enumerate (GDBusConnection *connection,
                   const gchar     *sender,
                   const gchar     *object_path,
                   gpointer         user_data)
{
  return dconf_writer_list_existing ();
}

static GDBusInterfaceInfo **
subtree_introspect (GDBusConnection *connection,
                    const gchar     *sender,
                    const gchar     *object_path,
                    const gchar     *node,
                    gpointer         user_data)
{
  /* The root node supports only the info iface */
  if (node == NULL)
    {
      const GDBusInterfaceInfo *interfaces[] = {
        &ca_desrt_dconf_WriterInfo, NULL
      };

      return g_memdup (interfaces, sizeof interfaces);
    }
  else
    {
      const GDBusInterfaceInfo *interfaces[] = {
        &ca_desrt_dconf_WriterInfo, &ca_desrt_dconf_Writer, NULL
      };

      return g_memdup (interfaces, sizeof interfaces);
    }
}

static void
bus_acquired (GDBusConnection *connection,
              const gchar     *name,
              gpointer         user_data)
{
  static GDBusSubtreeVTable vtable = {
    subtree_enumerate, subtree_introspect, subtree_dispatch
  };
  GDBusSubtreeFlags flags;

  flags = G_DBUS_SUBTREE_FLAGS_DISPATCH_TO_UNENUMERATED_NODES;
  g_dbus_connection_register_subtree (connection, "/ca/desrt/dconf/Writer",
                                      &vtable, flags, NULL, NULL, NULL);
}

static void
name_acquired (GDBusConnection *connection,
               const gchar     *name,
               gpointer         user_data)
{
}

static void
name_lost (GDBusConnection *connection,
           const gchar     *name,
           gpointer         user_data)
{
  g_error ("unable to acquire name: '%s'", name);
}

int
main (void)
{
  g_type_init ();

  dconf_writer_init ();

  g_bus_own_name (G_BUS_TYPE_SESSION, "ca.desrt.dconf", 0,
                  bus_acquired, name_acquired, name_lost, NULL, NULL);

  g_main_loop_run (g_main_loop_new (NULL, FALSE));

  return 0;
}
