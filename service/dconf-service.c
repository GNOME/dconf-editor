/*
 * Copyright © 2012 Canonical Limited
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

#include "dconf-service.h"

#include "dconf-generated.h"
#include "dconf-writer.h"
#include "dconf-blame.h"

#include <string.h>
#include <fcntl.h>

typedef GApplicationClass DConfServiceClass;
typedef struct
{
  GApplication parent_instance;

  DConfBlame  *blame;
  GHashTable  *writers;
  guint        subtree_id;
} DConfService;

G_DEFINE_TYPE (DConfService, dconf_service, G_TYPE_APPLICATION)

static gboolean
dconf_service_signalled (gpointer user_data)
{
  DConfService *service = user_data;

  g_application_release (G_APPLICATION (service));

  return G_SOURCE_REMOVE;
}

static gchar **
string_set_free (GHashTable *set)
{
  GHashTableIter iter;
  gchar **result;
  gint n_items;
  gpointer key;
  gint i = 0;

  n_items = g_hash_table_size (set);
  result = g_new (gchar *, n_items + 1);

  g_hash_table_iter_init (&iter, set);
  while (g_hash_table_iter_next (&iter, &key, NULL))
    {
      result[i++] = key;
      g_hash_table_iter_steal (&iter);
    }
  result[i] = NULL;

  g_assert_cmpint (n_items, ==, i);
  g_hash_table_unref (set);

  return result;
}

static GHashTable *
string_set_new (void)
{
  return g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);
}

static void
string_set_add (GHashTable  *set,
                const gchar *string)
{
  g_hash_table_add (set, g_strdup (string));
}

static gchar **
dconf_service_subtree_enumerate (GDBusConnection *connection,
                                 const gchar     *sender,
                                 const gchar     *object_path,
                                 gpointer         user_data)
{
  DConfService *service = user_data;
  GHashTableIter iter;
  GHashTable *set;
  gpointer key;

  set = string_set_new ();
  g_hash_table_iter_init (&iter, service->writers);
  while (g_hash_table_iter_next (&iter, &key, NULL))
    string_set_add (set, key);

  return string_set_free (set);
}

GDBusInterfaceInfo **
dconf_service_subtree_introspect (GDBusConnection *connection,
                                  const gchar     *sender,
                                  const gchar     *object_path,
                                  const gchar     *node,
                                  gpointer         user_data)
{
  GDBusInterfaceInfo **result;

  if (node == NULL)
    return NULL;

  result = g_new (GDBusInterfaceInfo *, 2);
  result[0] = dconf_dbus_writer_interface_info ();
  result[1] = NULL;

  return result;
}

static gpointer
dconf_service_get_writer (DConfService    *service,
                          GDBusConnection *connection,
                          const gchar     *base_path,
                          const gchar     *name)
{
  GDBusInterfaceSkeleton *writer;

  writer = g_hash_table_lookup (service->writers, name);

  if (writer == NULL)
    {
      GError *error = NULL;
      gchar *object_path;

      writer = dconf_writer_new (DCONF_TYPE_WRITER, name);
      g_hash_table_insert (service->writers, g_strdup (name), writer);
      object_path = g_strjoin ("/", base_path, name, NULL);
      g_dbus_interface_skeleton_export (writer, connection, object_path, &error);
      g_assert_no_error (error);
      g_free (object_path);
    }

  return writer;
}

const GDBusInterfaceVTable *
dconf_service_subtree_dispatch (GDBusConnection *connection,
                                const gchar     *sender,
                                const gchar     *object_path,
                                const gchar     *interface_name,
                                const gchar     *node,
                                gpointer        *out_user_data,
                                gpointer         user_data)
{
  DConfService *service = user_data;

  g_assert_cmpstr (interface_name, ==, "ca.desrt.dconf.Writer");
  g_assert (node != NULL);

  *out_user_data = dconf_service_get_writer (service, connection, object_path, node);

  return g_dbus_interface_skeleton_get_vtable (*out_user_data);
}

static gboolean
dconf_service_dbus_register (GApplication     *application,
                             GDBusConnection  *connection,
                             const gchar      *object_path,
                             GError          **error)
{
  const GDBusSubtreeVTable subtree_vtable = {
    dconf_service_subtree_enumerate,
    dconf_service_subtree_introspect,
    dconf_service_subtree_dispatch
  };
  DConfService *service = DCONF_SERVICE (application);
  GError *local_error = NULL;

  service->blame = dconf_blame_get ();
  if (service->blame)
    {
      g_dbus_interface_skeleton_export (G_DBUS_INTERFACE_SKELETON (service->blame),
                                        connection, object_path, &local_error);
      g_assert_no_error (local_error);
    }

  service->subtree_id = g_dbus_connection_register_subtree (connection, "/ca/desrt/dconf/Writer", &subtree_vtable,
                                                            G_DBUS_SUBTREE_FLAGS_DISPATCH_TO_UNENUMERATED_NODES,
                                                            g_object_ref (service), g_object_unref, &local_error);
  g_assert_no_error (local_error);

  return TRUE;
}

static void
dconf_service_dbus_unregister (GApplication    *application,
                               GDBusConnection *connection,
                               const gchar     *object_path)
{
  DConfService *service = DCONF_SERVICE (application);

  if (service->blame)
    {
      g_dbus_interface_skeleton_unexport (G_DBUS_INTERFACE_SKELETON (service->blame));
      g_object_unref (service->blame);
      service->blame = NULL;
    }

  g_dbus_connection_unregister_subtree (connection, service->subtree_id);
  service->subtree_id = 0;
}

static void
dconf_service_startup (GApplication *application)
{
  DConfService *service = DCONF_SERVICE (application);

  G_APPLICATION_CLASS (dconf_service_parent_class)
    ->startup (application);

  g_unix_signal_add (SIGTERM, dconf_service_signalled, service);
  g_unix_signal_add (SIGINT, dconf_service_signalled, service);
  g_unix_signal_add (SIGHUP, dconf_service_signalled, service);

  g_application_hold (application);
}

static void
dconf_service_shutdown (GApplication *application)
{
  G_APPLICATION_CLASS (dconf_service_parent_class)
    ->shutdown (application);
}

static void
dconf_service_init (DConfService *service)
{
  service->writers = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, g_object_unref);
}

static void
dconf_service_class_init (GApplicationClass *class)
{
  class->dbus_register = dconf_service_dbus_register;
  class->dbus_unregister = dconf_service_dbus_unregister;
  class->startup = dconf_service_startup;
  class->shutdown = dconf_service_shutdown;
}

GApplication *
dconf_service_new (void)
{
  return g_object_new (DCONF_TYPE_SERVICE,
                       "application-id", "ca.desrt.dconf",
                       "flags", G_APPLICATION_IS_SERVICE,
                       NULL);
}
