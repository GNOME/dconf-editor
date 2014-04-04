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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "config.h"

#include "dconf-service.h"

#include "dconf-generated.h"
#include "dconf-writer.h"
#include "dconf-blame.h"

#include <glib-unix.h>
#include <string.h>
#include <fcntl.h>

typedef GApplicationClass DConfServiceClass;
typedef struct
{
  GApplication parent_instance;

  GIOExtensionPoint *extension_point;

  DConfBlame  *blame;
  GHashTable  *writers;
  GArray      *subtree_ids;

  gboolean     released;
} DConfService;

G_DEFINE_TYPE (DConfService, dconf_service, G_TYPE_APPLICATION)

static gboolean
dconf_service_signalled (gpointer user_data)
{
  DConfService *service = user_data;

  if (!service->released)
    g_application_release (G_APPLICATION (service));

  service->released = TRUE;

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

static GType
dconf_service_find_writer_type (DConfService  *service,
                                const gchar   *object_path,
                                GHashTable   **writers)
{
  GIOExtension *extension;
  const gchar *path;
  GHashTable *table;

  path = object_path + strlen ("/ca/desrt/dconf");
  g_assert (*path == '/');
  path++;

  extension = g_io_extension_point_get_extension_by_name (service->extension_point, path);
  g_assert (extension != NULL);

  table = g_hash_table_lookup (service->writers, path);
  if (table == NULL)
    {
      table = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, g_object_unref);
      g_hash_table_insert (service->writers, g_strdup (path), table);
    }

  *writers = table;

  return g_io_extension_get_type (extension);
}

static gchar **
dconf_service_subtree_enumerate (GDBusConnection *connection,
                                 const gchar     *sender,
                                 const gchar     *object_path,
                                 gpointer         user_data)
{
  DConfService *service = user_data;
  GHashTableIter iter;
  GHashTable *writers;
  GType writer_type;
  GHashTable *set;
  gpointer key;

  set = string_set_new ();
  writer_type = dconf_service_find_writer_type (service, object_path, &writers);
  g_hash_table_iter_init (&iter, writers);
  while (g_hash_table_iter_next (&iter, &key, NULL))
    string_set_add (set, key);

  dconf_writer_list (writer_type, set);

  return string_set_free (set);
}

static GDBusInterfaceInfo **
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
  GHashTable *writers;
  GType writer_type;

  writer_type = dconf_service_find_writer_type (service, base_path, &writers);

  writer = g_hash_table_lookup (writers, name);

  if (writer == NULL)
    {
      GError *error = NULL;
      gchar *object_path;

      writer = dconf_writer_new (writer_type, name);
      g_hash_table_insert (writers, g_strdup (name), writer);
      object_path = g_strjoin ("/", base_path, name, NULL);
      g_dbus_interface_skeleton_export (writer, connection, object_path, &error);
      g_assert_no_error (error);
      g_free (object_path);
    }

  return writer;
}

static const GDBusInterfaceVTable *
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
  GList *node;
  guint id;

  service->extension_point = g_io_extension_point_register ("dconf-backend");
  g_io_extension_point_set_required_type (service->extension_point, DCONF_TYPE_WRITER);
  g_io_extension_point_implement ("dconf-backend", DCONF_TYPE_WRITER, "Writer", 0);
  g_io_extension_point_implement ("dconf-backend", DCONF_TYPE_KEYFILE_WRITER, "keyfile", 0);
  g_io_extension_point_implement ("dconf-backend", DCONF_TYPE_SHM_WRITER, "shm", 0);

  service->blame = dconf_blame_get ();
  if (service->blame)
    {
      g_dbus_interface_skeleton_export (G_DBUS_INTERFACE_SKELETON (service->blame),
                                        connection, object_path, &local_error);
      g_assert_no_error (local_error);
    }

  for (node = g_io_extension_point_get_extensions (service->extension_point); node; node = node->next)
    {
      gchar *path;

      path = g_strconcat ("/ca/desrt/dconf/", g_io_extension_get_name (node->data), NULL);
      id = g_dbus_connection_register_subtree (connection, path, &subtree_vtable,
                                               G_DBUS_SUBTREE_FLAGS_DISPATCH_TO_UNENUMERATED_NODES,
                                               g_object_ref (service), g_object_unref, &local_error);
      g_assert_no_error (local_error);
      g_array_append_vals (service->subtree_ids, &id, 1);
      g_free (path);
    }

  return TRUE;
}

static void
dconf_service_dbus_unregister (GApplication    *application,
                               GDBusConnection *connection,
                               const gchar     *object_path)
{
  DConfService *service = DCONF_SERVICE (application);
  gint i;

  if (service->blame)
    {
      g_dbus_interface_skeleton_unexport (G_DBUS_INTERFACE_SKELETON (service->blame));
      g_object_unref (service->blame);
      service->blame = NULL;
    }

  for (i = 0; i < service->subtree_ids->len; i++)
    g_dbus_connection_unregister_subtree (connection, g_array_index (service->subtree_ids, guint, i));
  g_array_set_size (service->subtree_ids, 0);
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
  service->subtree_ids = g_array_new (FALSE, TRUE, sizeof (guint));
}

static void
dconf_service_finalize (GObject *object)
{
  DConfService *service = (DConfService *) object;

  g_assert_cmpint (service->subtree_ids->len, ==, 0);
  g_array_free (service->subtree_ids, TRUE);

  G_OBJECT_CLASS (dconf_service_parent_class)->finalize (object);
}

static void
dconf_service_class_init (GApplicationClass *class)
{
  GObjectClass *object_class = G_OBJECT_CLASS (class);

  object_class->finalize = dconf_service_finalize;

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
