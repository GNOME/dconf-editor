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

#include <glib-unix.h>
#include <gio/gio.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "dconf-interfaces.h"
#include "../common/dconf-changeset.h"
#include "dconf-writer.h"
#include "dconf-state.h"

static void
emit_notify_signal (GDBusConnection  *connection,
                    DConfWriter      *writer,
                    const gchar      *tag,
                    const gchar      *prefix,
                    const gchar     **keys,
                    guint             n_keys)
{
  GVariantBuilder builder;
  GVariant *items;
  gchar *path;
  gchar *obj;

  g_variant_builder_init (&builder, G_VARIANT_TYPE ("as"));

  if (n_keys > 1)
    {
      const gchar *last_reset = NULL;
      gint last_reset_len = 0;
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

  obj = g_strjoin (NULL, "/ca/desrt/dconf/Writer/",
                   dconf_writer_get_name (writer), NULL);
  g_dbus_connection_emit_signal (connection, NULL, obj,
                                 "ca.desrt.dconf.Writer", "Notify",
                                 g_variant_new ("(s@ass)",
                                                path, items, tag),
                                 NULL);
  g_free (path);
  g_free (obj);
}

static void
emit_notify_signal_change (GDBusConnection *connection,
                           DConfWriter     *writer,
                           gchar           *tag,
                           DConfChangeset  *change)
{
  const gchar *path;
  const gchar * const *names;

  if (dconf_changeset_describe (change, &path, &names, NULL))
    {
      gchar *obj;

      obj = g_strjoin (NULL, "/ca/desrt/dconf/Writer/", dconf_writer_get_name (writer), NULL);
      g_dbus_connection_emit_signal (connection, NULL, obj,
                                     "ca.desrt.dconf.Writer", "Notify",
                                     g_variant_new ("(s^ass)", path, names, tag),
                                     NULL);
      g_free (obj);
    }
}

static void
unwrap_maybe_and_variant (GVariant **ptr)
{
  GVariant *array, *child;
  gsize n_children;

  array = *ptr;
  n_children = g_variant_n_children (array);

  switch (n_children)
    {
    case 0:
      child = NULL;
      break;
    case 1: default:
      g_variant_get_child (array, 0, "v", &child);
      break;
    case 2:
      {
        GVariant *untrusted;
        GVariant *trusted;
        GVariant *ay;

        g_variant_get_child (array, 0, "v", &ay);
        if (!g_variant_is_of_type (ay, G_VARIANT_TYPE_BYTESTRING))
          {
            g_variant_unref (ay);
            child = NULL;
            break;
          }

        untrusted = g_variant_new_from_data (G_VARIANT_TYPE_VARIANT,
                                             g_variant_get_data (ay),
                                             g_variant_get_size (ay),
                                             FALSE,
                                             (GDestroyNotify) g_variant_unref, ay);
        g_variant_ref_sink (untrusted);
        trusted = g_variant_get_normal_form (untrusted);
        g_variant_unref (untrusted);

        g_variant_get (trusted, "v", &child);
      }
    }

  g_variant_unref (array);
  *ptr = child;
}

static void
gather_blame_info (DConfState      *state,
                   GDBusConnection *connection,
                   const gchar     *sender,
                   const gchar     *object_path,
                   const gchar     *method_name,
                   GVariant        *parameters)
{
  GError *error = NULL;
  GVariant *reply;
  GString *info;

  if (state->blame_info == NULL)
    state->blame_info = g_string_new (NULL);
  else
    g_string_append (state->blame_info, "\n====================================================================\n");

  info = state->blame_info;

  g_string_append_printf (info, "Sender: %s\n", sender);
  g_string_append_printf (info, "Object path: %s\n", object_path);
  g_string_append_printf (info, "Method: %s\n", method_name);

  if (parameters)
    {
      gchar *tmp;

      tmp = g_variant_print (parameters, FALSE);
      g_string_append_printf (info, "Parameters: %s\n", tmp);
      g_free (tmp);
    }

  reply = g_dbus_connection_call_sync (connection, "org.freedesktop.DBus", "/", "org.freedesktop.DBus",
                                       "GetConnectionUnixProcessID", g_variant_new ("(s)", sender),
                                       G_VARIANT_TYPE ("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);

  if (reply != NULL)
    {
      guint pid;

      g_variant_get (reply, "(u)", &pid);
      g_string_append_printf (info, "PID: %u\n", pid);
      g_variant_unref (reply);
    }
  else
    {
      g_string_append_printf (info, "Unable to acquire PID: %s\n", error->message);
      g_error_free (error);
    }

  {
    const gchar * const ps_fx[] = { "ps", "fx", NULL };
    gchar *result_out;
    gchar *result_err;
    gint status;

    if (g_spawn_sync (NULL, (gchar **) ps_fx, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL,
                      &result_out, &result_err, &status, &error))
      {
        g_string_append (info, "\n=== Process table from time of call follows ('ps fx') ===\n");
        g_string_append (info, result_out);
        g_string_append (info, result_err);
        g_string_append_printf (info, "\nps exit status: %u\n", status);
      }
    else
      {
        g_string_append_printf (info, "\nUnable to spawn 'ps fx': %s\n", error->message);
        g_error_free (error);
      }
  }
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
  DConfState *state;

  state = dconf_writer_get_state (writer);

  /* debugging... */
  if G_UNLIKELY (state->blame_mode)
    gather_blame_info (state, connection, sender, object_path, method_name, parameters);

  if (strcmp (method_name, "Change") == 0)
    {
      DConfChangeset *change;
      GError *error = NULL;
      GVariant *args;
      GVariant *tmp;
      gchar *tag;

      tmp = g_variant_new_from_data (G_VARIANT_TYPE ("a{smv}"),
                                     g_variant_get_data (parameters), g_variant_get_size (parameters), FALSE,
                                     (GDestroyNotify) g_variant_unref, g_variant_ref (parameters));
      g_variant_ref_sink (tmp);
      args = g_variant_get_normal_form (tmp);
      g_variant_unref (tmp);

      change = dconf_changeset_deserialise (args);
      g_variant_unref (args);

      if (!dconf_writer_change (writer, change, &error))
        {
          g_dbus_method_invocation_return_gerror (invocation, error);
          g_error_free (error);
          return;
        }

      tag = dconf_state_get_tag (state);
      g_dbus_method_invocation_return_value (invocation, g_variant_new ("(s)", tag));
      emit_notify_signal_change (connection, writer, tag, change);
      dconf_changeset_unref (change);
      g_free (tag);
    }

  else if (strcmp (method_name, "Write") == 0)
    {
      GError *error = NULL;
      GVariant *keyvalue;
      const gchar *key;
      gsize key_length;
      GVariant *value;
      GVariant *none;
      gchar *path;
      gchar *tag;

      g_variant_get (parameters, "(@s@av)", &keyvalue, &value);
      key = g_variant_get_string (keyvalue, &key_length);
      g_variant_unref (keyvalue);
      unwrap_maybe_and_variant (&value);

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
          if (value != NULL)
            g_variant_unref (value);
          return;
        }

      if (!dconf_writer_write (writer, key, value, &error))
        {
          g_dbus_method_invocation_return_gerror (invocation, error);
          if (value != NULL)
            g_variant_unref (value);
          g_error_free (error);
          return;
        }

      tag = dconf_state_get_tag (state);
      g_dbus_method_invocation_return_value (invocation,
                                             g_variant_new ("(s)", tag));
      none = g_variant_new_array (G_VARIANT_TYPE_STRING, NULL, 0);
      path = g_strjoin (NULL, "/ca/desrt/dconf/Writer/",
                        dconf_writer_get_name (writer), NULL);
      g_dbus_connection_emit_signal (connection, NULL, path,
                                     "ca.desrt.dconf.Writer", "Notify",
                                     g_variant_new ("(s@ass)",
                                                    key, none, tag),
                                     NULL);
      if (value != NULL)
        g_variant_unref (value);
      g_free (path);
      g_free (tag);
    }

  else if (strcmp (method_name, "WriteMany") == 0)
    {
      GError *error = NULL;
      const gchar *prefix;
      GVariantIter *iter;
      const gchar **keys;
      GVariant **values;
      gsize length;
      gchar *tag;
      gint i = 0;
      gint j;

      g_variant_get (parameters, "(&sa(sav))", &prefix, &iter);
      length = g_variant_iter_n_children (iter);

      keys = g_new (const gchar *, length + 1);
      values = g_new (GVariant *, length);
      while (g_variant_iter_next (iter, "(&s@av)", &keys[i], &values[i]))
        {
          unwrap_maybe_and_variant (&values[i]);

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

      tag = dconf_state_get_tag (state);
      g_dbus_method_invocation_return_value (invocation,
                                             g_variant_new ("(s)", tag));
      emit_notify_signal (connection, writer, tag, prefix, keys, i);

      for (j = 0; j < i; j++)
        if (values[j] != NULL)
          g_variant_unref (values[j]);

      g_free (values);
      g_free (keys);
      g_free (tag);
    }

  else
    g_assert_not_reached ();
}

static void
writer_info_method (GDBusConnection       *connection,
                    const gchar           *sender,
                    const gchar           *object_path,
                    const gchar           *interface_name,
                    const gchar           *method_name,
                    GVariant              *parameters,
                    GDBusMethodInvocation *invocation,
                    gpointer               user_data)
{
  DConfState *state = user_data;

  /* only record this if it's the first */
  if G_UNLIKELY (state->blame_mode && state->blame_info == NULL)
    gather_blame_info (state, connection, sender, object_path, method_name, parameters);

  if (g_str_equal (method_name, "Blame"))
    {
      if (state->blame_info == NULL)
        state->blame_info = g_string_new ("DCONF_BLAME is not in the environment of dconf-service\n");

      g_dbus_method_invocation_return_value (invocation, g_variant_new ("(s)", state->blame_info->str));
    }

  else
    g_assert_not_reached ();
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
  DConfState *state = user_data;

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
          writer = dconf_writer_new (state, node);
          g_hash_table_insert (writer_table, g_strdup (node), writer);
        }

      *out_user_data = writer;

      return &vtable;
    }

  else if (strcmp (interface_name, "ca.desrt.dconf.WriterInfo") == 0)
    {
      static const GDBusInterfaceVTable vtable = {
        writer_info_method, NULL
      };

      *out_user_data = state;
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
  DConfState *state = user_data;
  GDBusSubtreeFlags flags;

  dconf_state_set_id (state, g_dbus_connection_get_unique_name (connection));

  flags = G_DBUS_SUBTREE_FLAGS_DISPATCH_TO_UNENUMERATED_NODES;
  g_dbus_connection_register_subtree (connection, "/ca/desrt/dconf/Writer",
                                      &vtable, flags, state, NULL, NULL);
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
  fprintf (stderr, "unable to acquire name: '%s'\n", name);
  exit (1);
}

static gboolean
exit_service (gpointer data)
{
  DConfState *state = data;

  g_main_loop_quit (state->main_loop);

  return TRUE;
}

int
main (void)
{
  DConfState state;
  GBusType type;

  g_type_init ();

  dconf_state_init (&state);

  if (state.is_session)
    type = G_BUS_TYPE_SESSION;
  else
    type = G_BUS_TYPE_SYSTEM;

  g_unix_signal_add (SIGTERM, exit_service, &state);
  g_unix_signal_add (SIGINT, exit_service, &state);
  g_unix_signal_add (SIGHUP, exit_service, &state);

  g_bus_own_name (type, "ca.desrt.dconf", G_BUS_NAME_OWNER_FLAGS_NONE,
                  bus_acquired, name_acquired, name_lost, &state, NULL);

  g_main_loop_run (state.main_loop);

  dconf_state_destroy (&state);

  return 0;
}
