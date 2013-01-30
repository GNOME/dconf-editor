/*
 * Copyright © 2010 Codethink Limited
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

#include "dconf-writer.h"

#include "../shm/dconf-shm.h"
#include "dconf-gvdb-utils.h"
#include "dconf-generated.h"
#include "dconf-blame.h"

#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>

struct _DConfWriterPrivate
{
  gchar *filename;
  gboolean native;
  gchar *basepath;
  gchar *name;
  guint64 tag;
  gboolean need_write;

  DConfChangeset *uncommited_values;
  DConfChangeset *commited_values;

  GQueue uncommited_changes;
  GQueue commited_changes;
};

typedef struct
{
  DConfChangeset *changeset;
  gchar          *tag;
} TaggedChange;

static void dconf_writer_iface_init (DConfDBusWriterIface *iface);

G_DEFINE_TYPE_WITH_CODE (DConfWriter, dconf_writer, DCONF_DBUS_TYPE_WRITER_SKELETON,
                         G_IMPLEMENT_INTERFACE (DCONF_DBUS_TYPE_WRITER, dconf_writer_iface_init))

static void
dconf_writer_real_list (GHashTable *set)
{
  const gchar *name;
  gchar *dirname;
  GDir *dir;

  dirname = g_build_filename (g_get_user_config_dir (), "dconf", NULL);
  dir = g_dir_open (dirname, 0, NULL);

  if (!dir)
    return;

  while ((name = g_dir_read_name (dir)))
    {
      if (!strchr (name, '.'))
        g_hash_table_add (set, g_strdup (name));
    }

  g_dir_close (dir);
}

static gchar *
dconf_writer_get_tag (DConfWriter *writer)
{
  GDBusConnection *connection;

  connection = g_dbus_interface_skeleton_get_connection (G_DBUS_INTERFACE_SKELETON (writer));

  return g_strdup_printf ("%s:%s:%" G_GUINT64_FORMAT,
                          g_dbus_connection_get_unique_name (connection),
                          writer->priv->name, writer->priv->tag++);
}

static gboolean
dconf_writer_real_begin (DConfWriter  *writer,
                         GError      **error)
{
  /* If this is the first time, populate the value table with the
   * existing values.
   */
  if (writer->priv->commited_values == NULL)
    {
      gboolean missing;

      writer->priv->commited_values = dconf_gvdb_utils_read_file (writer->priv->filename, &missing, error);

      if (!writer->priv->commited_values)
        return FALSE;

      /* If this is a non-native writer and the file doesn't exist, we
       * will need to write it on commit so that the client can open it.
       */
      if (missing && !writer->priv->native)
        writer->priv->need_write = TRUE;
    }

  writer->priv->uncommited_values = dconf_changeset_new_database (writer->priv->commited_values);

  return TRUE;
}

static void
dconf_writer_real_change (DConfWriter    *writer,
                          DConfChangeset *changeset,
                          const gchar    *tag)
{
  g_return_if_fail (writer->priv->uncommited_values != NULL);

  dconf_changeset_change (writer->priv->uncommited_values, changeset);

  if (tag)
    {
      TaggedChange *change;

      change = g_slice_new (TaggedChange);
      change->changeset = dconf_changeset_ref (changeset);
      change->tag = g_strdup (tag);

      g_queue_push_tail (&writer->priv->uncommited_changes, change);
    }

  writer->priv->need_write = TRUE;
}

static gboolean
dconf_writer_real_commit (DConfWriter  *writer,
                          GError      **error)
{
  gint invalidate_fd = -1;

  if (!writer->priv->need_write)
    {
      g_assert (g_queue_is_empty (&writer->priv->uncommited_changes));
      g_assert (g_queue_is_empty (&writer->priv->commited_changes));
      dconf_changeset_unref (writer->priv->uncommited_values);
      writer->priv->uncommited_values = NULL;

      return TRUE;
    }

  if (!writer->priv->native)
    /* If it fails, it doesn't matter... */
    invalidate_fd = open (writer->priv->filename, O_WRONLY);

  if (!dconf_gvdb_utils_write_file (writer->priv->filename, writer->priv->uncommited_values, error))
    return FALSE;

  if (writer->priv->native)
    dconf_shm_flag (writer->priv->name);

  if (invalidate_fd != -1)
    {
      write (invalidate_fd, "\0\0\0\0\0\0\0\0", 8);
      close (invalidate_fd);
    }

  if (writer->priv->commited_values)
    dconf_changeset_unref (writer->priv->commited_values);
  writer->priv->commited_values = writer->priv->uncommited_values;
  writer->priv->uncommited_values = NULL;

  {
    GQueue empty_queue = G_QUEUE_INIT;

    g_assert (g_queue_is_empty (&writer->priv->commited_changes));
    writer->priv->commited_changes = writer->priv->uncommited_changes;
    writer->priv->uncommited_changes = empty_queue;
  }

  return TRUE;
}

static void
dconf_writer_real_end (DConfWriter *writer)
{
  while (!g_queue_is_empty (&writer->priv->uncommited_changes))
    {
      TaggedChange *change = g_queue_pop_head (&writer->priv->uncommited_changes);
      dconf_changeset_unref (change->changeset);
      g_free (change->tag);
      g_slice_free (TaggedChange, change);
    }

  while (!g_queue_is_empty (&writer->priv->commited_changes))
    {
      TaggedChange *change = g_queue_pop_head (&writer->priv->commited_changes);
      const gchar *prefix;
      const gchar * const *paths;
      guint n;

      n = dconf_changeset_describe (change->changeset, &prefix, &paths, NULL);
      g_assert (n != 0);
      dconf_dbus_writer_emit_notify_signal (DCONF_DBUS_WRITER (writer), prefix, paths, change->tag);
      dconf_changeset_unref (change->changeset);
      g_free (change->tag);
      g_slice_free (TaggedChange, change);
    }

  g_clear_pointer (&writer->priv->uncommited_values, dconf_changeset_unref);
}

gboolean
dconf_writer_begin (DConfWriter  *writer,
                    GError      **error)
{
  return DCONF_WRITER_GET_CLASS (writer)->begin (writer, error);
}

void
dconf_writer_change (DConfWriter    *writer,
                     DConfChangeset *changeset,
                     const gchar    *tag)
{
  DCONF_WRITER_GET_CLASS (writer)->change (writer, changeset, tag);
}

gboolean
dconf_writer_commit (DConfWriter  *writer,
                     GError      **error)
{
  return DCONF_WRITER_GET_CLASS (writer)->commit (writer, error);
}

void
dconf_writer_end (DConfWriter *writer)
{
  return DCONF_WRITER_GET_CLASS (writer)->end (writer);
}

static gboolean
dconf_writer_handle_init (DConfDBusWriter       *dbus_writer,
                          GDBusMethodInvocation *invocation)
{
  DConfWriter *writer = DCONF_WRITER (dbus_writer);
  GError *error = NULL;

  dconf_blame_record (invocation);

  dconf_writer_begin (writer, &error) && dconf_writer_commit (writer, &error);

  if (error)
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      g_error_free (error);
    }

  else
    g_dbus_method_invocation_return_value (invocation, NULL);

  dconf_writer_end (writer);

  return TRUE;
}

static gboolean
dconf_writer_handle_change (DConfDBusWriter       *dbus_writer,
                            GDBusMethodInvocation *invocation,
                            GVariant              *blob)
{
  DConfWriter *writer = DCONF_WRITER (dbus_writer);
  DConfChangeset *changeset;
  GError *error = NULL;
  GVariant *tmp, *args;
  gchar *tag;

  dconf_blame_record (invocation);

  tmp = g_variant_new_from_data (G_VARIANT_TYPE ("a{smv}"),
                                 g_variant_get_data (blob), g_variant_get_size (blob), FALSE,
                                 (GDestroyNotify) g_variant_unref, g_variant_ref (blob));
  g_variant_ref_sink (tmp);
  args = g_variant_get_normal_form (tmp);
  g_variant_unref (tmp);

  changeset = dconf_changeset_deserialise (args);
  g_variant_unref (args);

  tag = dconf_writer_get_tag (writer);

  /* Don't bother with empty changesets... */
  if (dconf_changeset_describe (changeset, NULL, NULL, NULL))
    {
      if (!dconf_writer_begin (writer, &error))
        goto out;

      dconf_writer_change (writer, changeset, tag);

      if (!dconf_writer_commit (writer, &error))
        goto out;
    }

out:
  dconf_changeset_unref (changeset);

  if (error)
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      g_error_free (error);
    }

  else
    g_dbus_method_invocation_return_value (invocation, g_variant_new ("(s)", tag));

  g_free (tag);

  dconf_writer_end (writer);

  return TRUE;
}

static void
dconf_writer_iface_init (DConfDBusWriterIface *iface)
{
  iface->handle_init = dconf_writer_handle_init;
  iface->handle_change = dconf_writer_handle_change;
}

static void
dconf_writer_init (DConfWriter *writer)
{
  writer->priv = G_TYPE_INSTANCE_GET_PRIVATE (writer, DCONF_TYPE_WRITER, DConfWriterPrivate);
  writer->priv->basepath = g_build_filename (g_get_user_config_dir (), "dconf", NULL);
  writer->priv->native = TRUE;
}

static void
dconf_writer_set_property (GObject *object, guint prop_id,
                           const GValue *value, GParamSpec *pspec)
{
  DConfWriter *writer = DCONF_WRITER (object);

  g_assert_cmpint (prop_id, ==, 1);

  g_assert (!writer->priv->name);
  writer->priv->name = g_value_dup_string (value);

  writer->priv->filename = g_build_filename (writer->priv->basepath, writer->priv->name, NULL);
}

static void
dconf_writer_class_init (DConfWriterClass *class)
{
  GObjectClass *object_class = G_OBJECT_CLASS (class);

  object_class->set_property = dconf_writer_set_property;

  class->begin = dconf_writer_real_begin;
  class->change = dconf_writer_real_change;
  class->commit = dconf_writer_real_commit;
  class->end = dconf_writer_real_end;
  class->list = dconf_writer_real_list;

  g_object_class_install_property (object_class, 1,
                                   g_param_spec_string ("name", "name", "name", NULL,
                                                        G_PARAM_STATIC_STRINGS | G_PARAM_CONSTRUCT_ONLY |
                                                        G_PARAM_WRITABLE));

  g_type_class_add_private (class, sizeof (DConfWriterPrivate));
}

void
dconf_writer_set_basepath (DConfWriter *writer,
                           const gchar *name)
{
  g_free (writer->priv->basepath);
  writer->priv->basepath = g_build_filename (g_get_user_runtime_dir (), "dconf-service", name, NULL);
  writer->priv->native = FALSE;
}

DConfChangeset *
dconf_writer_diff (DConfWriter    *writer,
                   DConfChangeset *changeset)
{
  return dconf_changeset_diff (writer->priv->uncommited_values, changeset);
}

const gchar *
dconf_writer_get_name (DConfWriter *writer)
{
  return writer->priv->name;
}

void
dconf_writer_list (GType       type,
                   GHashTable *set)
{
  DConfWriterClass *class;

  g_return_if_fail (g_type_is_a (type, DCONF_TYPE_WRITER));

  class = g_type_class_ref (type);
  class->list (set);
  g_type_class_unref (class);
}

GDBusInterfaceSkeleton *
dconf_writer_new (GType        type,
                  const gchar *name)
{
  g_return_val_if_fail (g_type_is_a (type, DCONF_TYPE_WRITER), NULL);

  return g_object_new (type, "name", name, NULL);
}
