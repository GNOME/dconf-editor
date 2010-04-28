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
#include "dconfdatabase.h"

#include <string.h>
#include <gdbus/gdbus.h>
#include "gvdb-reader.h"

typedef struct _Outstanding Outstanding;

struct _DConfDatabase
{
  GStaticMutex lock;

  GDBusConnection *bus;
  GvdbTable *value_table;
  GSList *backends;
  const gchar *context;

  Outstanding *outstanding;
  guint64 anti_expose;
};

struct _Outstanding
{
  Outstanding *next;

  volatile guint32 serial;

  gchar *reset_path, *set_key;
  GVariant *set_value;

  GTree *tree;
};

static volatile guint32 *
dconf_database_new_outstanding (DConfDatabase *database,
                                const gchar   *reset_path,
                                const gchar   *set_key,
                                GVariant      *set_value,
                                GTree         *tree)
{
  Outstanding *outstanding;

  outstanding = g_slice_new (Outstanding);
  outstanding->serial = 0;
  outstanding->reset_path = g_strdup (reset_path);
  outstanding->set_key = g_strdup (set_key);

  if (set_value)
    outstanding->set_value = g_variant_ref (set_value);
  else
    outstanding->set_value = NULL;

  if (tree)
    outstanding->tree = g_tree_ref (tree);
  else
    outstanding->tree = NULL;

  g_static_mutex_lock (&database->lock);
  outstanding->next = database->outstanding;
  database->outstanding = outstanding;
  g_static_mutex_unlock (&database->lock);

  return &outstanding->serial;
}

static gboolean
dconf_database_remove_outstanding (DConfDatabase *database,
                                   GDBusMessage  *message,
                                   guint64       *anti_expose)
{
  Outstanding **node;
  guint32 serial;

  if G_LIKELY (database->outstanding == NULL)
    return FALSE;

  serial = g_dbus_message_get_reply_serial (message);

  if (serial == 0)
    return FALSE;

  g_static_mutex_lock (&database->lock);

  /* this could be made more asymptotically efficient by using a queue
   * or a double-linked list with a 'tail' pointer but the usual case
   * here will be one outstanding item and very rarely more than a few.
   *
   * so we scan...
   */
  for (node = &database->outstanding; *node; node = &(*node)->next)
    if ((*node)->serial == serial)
      {
        Outstanding *tmp;

        tmp = *node;
        *node = tmp->next;

        g_static_mutex_unlock (&database->lock);

        g_variant_get (g_dbus_message_get_body (message), "(t)", anti_expose);

        g_free (tmp->reset_path);
        g_free (tmp->set_key);

        if (tmp->set_value)
          g_variant_unref (tmp->set_value);

        if (tmp->tree)
          g_tree_unref (tmp->tree);

        return TRUE;
      }

  g_static_mutex_unlock (&database->lock);

  return FALSE;
}

static gboolean
dconf_database_scan_outstanding_tree (GTree       *tree,
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
dconf_database_scan_outstanding (DConfDatabase  *database,
                                 const gchar    *key,
                                 GVariant      **value)
{
  Outstanding *node;
  gsize length;

  length = strlen (key);

  if G_LIKELY (database->outstanding == NULL)
    return FALSE;

  g_static_mutex_lock (&database->lock);

  for (node = database->outstanding; node; node = node->next)
    {
      if (node->reset_path)
        {
          if (g_str_has_prefix (key, node->reset_path))
            {
              *value = NULL;
              return TRUE;
            }
        }

      else if (node->set_key)
        {
          if (strcmp (key, node->set_key) == 0)
            {
              if (node->set_value != NULL)
                *value = g_variant_ref (*value);
              else
                *value = NULL;

              return TRUE;
            }
        }

      else
        {
          gpointer result;

          if (dconf_database_scan_outstanding_tree (node->tree, key,
                                                    length, &result))
            {
              if (result)
                *value = g_variant_ref (result);
              else
                *value = NULL;

              return TRUE;
            }
        }
    }

  g_static_mutex_unlock (&database->lock);

  return FALSE;
}

static void
dconf_database_reopen_file (DConfDatabase *database)
{
  gchar *filename;

  if (database->value_table != NULL)
    gvdb_table_unref (database->value_table);

  filename = g_build_filename (g_get_user_config_dir (), "dconf", NULL);
  database->value_table = gvdb_table_new (filename, FALSE, NULL);
  g_free (filename);
}

GVariant *
dconf_database_read (DConfDatabase *database,
                     const gchar   *key)
{
  GVariant *value;

  if (dconf_database_scan_outstanding (database, key, &value))
    return value;

  if (database->value_table == NULL)
    return NULL;

  dconf_database_reopen_file (database);

  return gvdb_table_get_value (database->value_table, key, NULL);
}

static void
dconf_database_incoming_signal (DConfDatabase *database,
                                GDBusMessage  *message)
{
  const gchar **keys;
  const gchar *name;
  guint64 serial;

  if (strcmp (g_dbus_message_get_interface (message),
              "ca.desrt.dconf.Writer") != 0 ||
      strcmp (g_dbus_message_get_member (message), "Notify") != 0)
    return;

  g_variant_get (g_dbus_message_get_body (message),
                 "(t&s^a&s)", &serial, &name, &keys);

  if (serial != database->anti_expose)
    {
      GSList *node;

      if (keys[0] == NULL)
        {
          for (node = database->backends; node; node = node->next)
            g_settings_backend_changed (node->data, name, NULL);
        }
      else
        {
          for (node = database->backends; node; node = node->next)
            g_settings_backend_keys_changed (node->data, name, keys, NULL);
        }
    }

  g_free (keys);
}

static gboolean
dconf_database_filter_function (GDBusConnection *connection,
                                GDBusMessage    *message,
                                gpointer         user_data)
{
  DConfDatabase *database = user_data;

  switch (g_dbus_message_get_type (message))
    {
    case G_DBUS_MESSAGE_TYPE_METHOD_RETURN:
      return dconf_database_remove_outstanding (database, message,
                                                &database->anti_expose);

    case G_DBUS_MESSAGE_TYPE_SIGNAL:
      dconf_database_incoming_signal (database, message);
      return FALSE;

    default:
      return FALSE;
    }
}

void
dconf_database_write_tree (DConfDatabase  *database,
                           GTree          *tree,
                           gpointer        origin_tag)
{
  volatile guint32 *serial;
  const gchar **keys;
  GVariant **values;
  gchar *path;

  serial = dconf_database_new_outstanding (database, NULL, NULL, NULL, tree);
  g_settings_backend_flatten_tree (tree, &path, &keys, &values);

  {
    GSList *node;

    for (node = database->backends; node; node = node->next)
      g_settings_backend_keys_changed (node->data, path,
                                       keys, origin_tag);
  }

  {
    GDBusMessage *message;
    GVariantBuilder args;
    gsize i;

    message =
      g_dbus_message_new_method_call ("ca.desrt.dconf", "/",
                                      "ca.desrt.dconf.Writer", "Write");

    g_variant_builder_init (&args, G_VARIANT_TYPE ("(ssa{smv})"));
    g_variant_builder_add (&args, "s", database->context);
    g_variant_builder_add (&args, "s", path);

    g_variant_builder_open (&args, G_VARIANT_TYPE ("a{smv}"));
    for (i = 0; keys[i]; i++)
      g_variant_builder_add (&args, "{smv}", keys[i], values[i]);

    g_variant_builder_close (&args);

    g_dbus_message_set_body (message,
                             g_variant_builder_end (&args));
    g_dbus_connection_send_message (database->bus,
                                    message, serial, NULL);
    g_object_unref (message);
  }

  g_free (path);
  g_free (keys);
  g_free (values);
}

gchar **
dconf_database_list (DConfDatabase *database,
                     const gchar   *path,
                     gsize         *length)
{
  gchar **result;

  result = gvdb_table_list (database->value_table, path);

  if (result)
    *length = g_strv_length (result);

  return result;
}

static void
dconf__message_set_body (GDBusMessage *message,
                         GVariant     *body)
{
  gchar *printed;

  g_variant_ref_sink (body);
  printed = g_variant_print (body, FALSE);
  g_variant_unref (body);

  g_dbus_message_set_body (message, g_variant_new ("(s)", printed));
  g_free (printed);
}

void
dconf_database_write (DConfDatabase *database,
                      const gchar   *path_or_key,
                      GVariant      *value,
                      gpointer       origin_tag)
{
  volatile guint32 *serial;
  GDBusMessage *message;

  serial = dconf_database_new_outstanding (database, NULL,
                                           path_or_key, value,
                                           NULL);

  message = g_dbus_message_new_method_call ("ca.desrt.dconf", "/",
                                            "ca.desrt.dconf.Writer", "Write");
  dconf__message_set_body (message, g_variant_new ("(smv)", path_or_key, value));
  g_dbus_connection_send_message (database->bus, message, serial, NULL);
  g_object_unref (message);

  {
    GSList *node;

    for (node = database->backends; node; node = node->next)
      g_settings_backend_changed (node->data, path_or_key, origin_tag);
  }
}

static void
send_match_rule (DConfDatabase *database,
                 const gchar   *method,
                 const gchar   *name)
{
  GDBusMessage *message;
  gchar *rule;

  rule = g_strdup_printf ("interface='ca.desrt.dconf.Writer',"
                          "arg1path='%s'", name);
  message = g_dbus_message_new_method_call ("org.freedesktop.DBus", "/",
                                            "org.freedesktop.DBus", method);
  g_dbus_message_set_body (message, g_variant_new ("(s)", (rule)));
  g_dbus_message_set_flags (message, G_DBUS_MESSAGE_FLAGS_NO_REPLY_EXPECTED);
  g_dbus_connection_send_message (database->bus, message, NULL, NULL);
  g_object_unref (message);
  g_free (rule);
}

void
dconf_database_subscribe (DConfDatabase *database,
                          const gchar   *name)
{
  send_match_rule (database, "AddMatch", name);
}

void
dconf_database_unsubscribe (DConfDatabase *database,
                            const gchar   *name)
{
  send_match_rule (database, "RemoveMatch", name);
}

DConfDatabase *
dconf_database_get_for_backend (gpointer backend)
{
  static gsize instance;

  if (g_once_init_enter (&instance))
    {
      DConfDatabase *database;

      database = g_slice_new0 (DConfDatabase);
      g_static_mutex_init (&database->lock);
      database->outstanding = NULL;
      database->backends = g_slist_prepend (database->backends, backend);
      database->bus = g_bus_get_sync (G_BUS_TYPE_SESSION, NULL, NULL);
      g_dbus_connection_add_filter (database->bus,
                                    dconf_database_filter_function,
                                    database, NULL);
      dconf_database_reopen_file (database);

      g_once_init_leave (&instance, (gsize) database);
    }

  return (DConfDatabase *) instance;
}
