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

#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

typedef DConfWriterClass DConfKeyfileWriterClass;

typedef struct
{
  DConfWriter   parent_instance;
  gchar        *filename;
  gchar        *lock_filename;
  gint          lock_fd;
  GFileMonitor *monitor;
  guint         scheduled_update;
  gchar        *contents;
  GKeyFile     *keyfile;
} DConfKeyfileWriter;

G_DEFINE_TYPE (DConfKeyfileWriter, dconf_keyfile_writer, DCONF_TYPE_WRITER)

DConfChangeset *
dconf_keyfile_to_changeset (GKeyFile    *keyfile,
                            const gchar *filename_fyi)
{
  DConfChangeset *changeset;
  gchar **groups;
  gint i;

  changeset = dconf_changeset_new_database (NULL);

  groups = g_key_file_get_groups (keyfile, NULL);
  for (i = 0; groups[i]; i++)
    {
      const gchar *group = groups[i];
      gchar *key_prefix;
      gchar **keys;
      gint j;

      /* Special case the [/] group to be able to contain keys at the
       * root (/a, /b, etc.).  All others must not start or end with a
       * slash (ie: group [x/y] contains keys such as /x/y/z).
       */
      if (!g_str_equal (group, "/"))
        {
          if (g_str_has_prefix (group, "/") || g_str_has_suffix (group, "/") || strstr (group, "//"))
            {
              g_warning ("%s: ignoring invalid group name: %s\n", filename_fyi, group);
              continue;
            }

          key_prefix = g_strconcat ("/", group, "/", NULL);
        }
      else
        key_prefix = g_strdup ("/");

      keys = g_key_file_get_keys (keyfile, group, NULL, NULL);
      g_assert (keys != NULL);

      for (j = 0; keys[j]; j++)
        {
          const gchar *key = keys[j];
          GError *error = NULL;
          gchar *value_str;
          GVariant *value;
          gchar *path;

          if (strchr (key, '/'))
            {
              g_warning ("%s: [%s]: ignoring invalid key name: %s\n", filename_fyi, group, key);
              continue;
            }

          value_str = g_key_file_get_value (keyfile, group, key, NULL);
          g_assert (value_str != NULL);

          value = g_variant_parse (NULL, value_str, NULL, NULL, &error);
          g_free (value_str);

          if (value == NULL)
            {
              g_warning ("%s: [%s]: %s: skipping invalid value: %s (%s)\n",
                         filename_fyi, group, key, value_str, error->message);
              g_error_free (error);
              continue;
            }

          path = g_strconcat (key_prefix, key, NULL);
          dconf_changeset_set (changeset, path, value);
          g_variant_unref (value);
          g_free (path);
        }

      g_free (key_prefix);
      g_strfreev (keys);
    }

  g_strfreev (groups);

  return changeset;
}

static void
dconf_keyfile_writer_list (GHashTable *set)
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
      const gchar *dottxt;

      dottxt = strstr (name, ".txt");

      if (dottxt && dottxt[4] == '\0')
        g_hash_table_add (set, g_strndup (name, dottxt - name));
    }

  g_dir_close (dir);
}

static gboolean dconf_keyfile_update (gpointer user_data);

static void
dconf_keyfile_changed (GFileMonitor      *monitor,
                       GFile             *file,
                       GFile             *other_file,
                       GFileMonitorEvent  event_type,
                       gpointer           user_data)
{
  DConfKeyfileWriter *kfw = user_data;

  if (event_type == G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT ||
      event_type == G_FILE_MONITOR_EVENT_CREATED)
    {
      if (!kfw->scheduled_update)
        kfw->scheduled_update = g_idle_add (dconf_keyfile_update, kfw);
    }
}

static gboolean
dconf_keyfile_writer_begin (DConfWriter  *writer,
                            GError      **error)
{
  DConfKeyfileWriter *kfw = (DConfKeyfileWriter *) writer;
  GError *local_error = NULL;
  DConfChangeset *contents;
  DConfChangeset *changes;

  if (kfw->filename == NULL)
    {
      gchar *filename_base;
      GFile *file;

      filename_base = g_build_filename (g_get_user_config_dir (), "dconf", dconf_writer_get_name (writer), NULL);
      kfw->filename = g_strconcat (filename_base, ".txt", NULL);
      kfw->lock_filename = g_strconcat (kfw->filename, "-lock", NULL);
      g_free (filename_base);

      /* See https://bugzilla.gnome.org/show_bug.cgi?id=691618 */
      file = g_vfs_get_file_for_path (g_vfs_get_local (), kfw->filename);
      kfw->monitor = g_file_monitor_file (file, G_FILE_MONITOR_NONE, NULL, NULL);
      g_object_unref (file);

      g_signal_connect (kfw->monitor, "changed", G_CALLBACK (dconf_keyfile_changed), kfw);
    }

  g_clear_pointer (&kfw->contents, g_free);

  kfw->lock_fd = open (kfw->lock_filename, O_RDWR | O_CREAT, 0666);
  if (kfw->lock_fd == -1)
    {
      gchar *dirname;

      /* Maybe it failed because the directory doesn't exist.  Try
       * again, after mkdir().
       */
      dirname = g_path_get_dirname (kfw->lock_filename);
      g_mkdir_with_parents (dirname, 0777);
      g_free (dirname);

      kfw->lock_fd = open (kfw->lock_filename, O_RDWR | O_CREAT, 0666);
      if (kfw->lock_fd == -1)
        {
          gint saved_errno = errno;

          g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (saved_errno),
                       "%s: %s", kfw->lock_filename, g_strerror (saved_errno));
          return FALSE;
        }
    }

  while (TRUE)
    {
      struct flock lock;

      lock.l_type = F_WRLCK;
      lock.l_whence = 0;
      lock.l_start = 0;
      lock.l_len = 0; /* lock all bytes */

      if (fcntl (kfw->lock_fd, F_SETLKW, &lock) == 0)
        break;

      if (errno != EINTR)
        {
          gint saved_errno = errno;

          g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (saved_errno),
                       "%s: unable to fcntl(F_SETLKW): %s", kfw->lock_filename, g_strerror (saved_errno));
          close (kfw->lock_fd);
          kfw->lock_fd = -1;
          return FALSE;
        }

      /* it was EINTR.  loop again. */
    }

  if (!g_file_get_contents (kfw->filename, &kfw->contents, NULL, &local_error))
    {
      if (!g_error_matches (local_error, G_FILE_ERROR, G_FILE_ERROR_NOENT))
        {
          g_propagate_error (error, local_error);
          return FALSE;
        }

      g_clear_error (&local_error);
    }

  kfw->keyfile = g_key_file_new ();

  if (kfw->contents)
    {
      if (!g_key_file_load_from_data (kfw->keyfile, kfw->contents, -1, G_KEY_FILE_KEEP_COMMENTS, &local_error))
        {
          g_clear_pointer (&kfw->keyfile, g_key_file_free);
          g_clear_pointer (&kfw->contents, g_free);
          g_propagate_error (error, local_error);
          return FALSE;
        }
    }

  if (!DCONF_WRITER_CLASS (dconf_keyfile_writer_parent_class)->begin (writer, error))
    {
      g_clear_pointer (&kfw->keyfile, g_key_file_free);
      return FALSE;
    }

  /* Diff the keyfile to the current contents of the database and apply
   * any changes that we notice.
   *
   * This will catch both the case of people outside of the service
   * making changes to the file and also the case of starting for the
   * first time.
   */
  contents = dconf_keyfile_to_changeset (kfw->keyfile, kfw->filename);
  changes = dconf_writer_diff (writer, contents);

  if (changes)
    {
      DCONF_WRITER_CLASS (dconf_keyfile_writer_parent_class)->change (writer, changes, "");
      dconf_changeset_unref (changes);
    }

  dconf_changeset_unref (contents);

  return TRUE;
}

static void
dconf_keyfile_writer_change (DConfWriter    *writer,
                             DConfChangeset *changeset,
                             const gchar    *tag)
{
  DConfKeyfileWriter *kfw = (DConfKeyfileWriter *) writer;
  const gchar *prefix;
  const gchar * const *paths;
  GVariant * const *values;
  guint n, i;

  DCONF_WRITER_CLASS (dconf_keyfile_writer_parent_class)->change (writer, changeset, tag);

  n = dconf_changeset_describe (changeset, &prefix, &paths, &values);

  for (i = 0; i < n; i++)
    {
      gchar *path = g_strconcat (prefix, paths[i], NULL);
      GVariant *value = values[i];

      if (g_str_equal (path, "/"))
        {
          g_assert (value == NULL);

          /* This is a request to reset everything.
           *
           * Easiest way to do this:
           */
          g_key_file_free (kfw->keyfile);
          kfw->keyfile = g_key_file_new ();
        }
      else if (g_str_has_suffix (path, "/"))
        {
          gchar *group_to_remove;
          gchar **groups;
          gint i;

          g_assert (value == NULL);

          /* Time to do a path reset.
           *
           * We must reset the group for the path plus any "subgroups".
           *
           * We dealt with the case of "/" above, so we know we have
           * something with at least a separate leading and trailing slash,
           * with the group name in the middle.
           */
          group_to_remove = g_strndup (path + 1, strlen (path) - 2);
          g_key_file_remove_group (kfw->keyfile, group_to_remove, NULL);
          g_free (group_to_remove);

          /* Now the rest...
           *
           * For this case we check if the group is prefixed by the path
           * given to us, including the trailing slash (but not the leading
           * one).  That means a reset on "/a/" (group "[a]") will match
           * group "[a/b]" but not will not match group "[another]".
           */
          groups = g_key_file_get_groups (kfw->keyfile, NULL);
          for (i = 0; groups[i]; i++)
            if (g_str_has_prefix (groups[i], path + 1)) /* remove only leading slash */
              g_key_file_remove_group (kfw->keyfile, groups[i], NULL);
          g_strfreev (groups);
        }
      else
        {
          /* A simple set or reset of a single key. */
          const gchar *last_slash;
          gchar *group;
          gchar *key;

          last_slash = strrchr (path, '/');

          /* If the last slash is the first one then the group will be the
           * special case: [/].  Otherwise we remove the leading and
           * trailing slashes.
           */
          if (last_slash != path)
            group = g_strndup (path + 1, last_slash - (path + 1));
          else
            group = g_strdup ("/");

          /* Key is the non-empty part following the last slash (we know
           * that it's non-empty because we dealt with strings ending with
           * '/' above).
           */
          key = g_strdup (last_slash + 1);

          if (value != NULL)
            {
              gchar *printed;

              printed = g_variant_print (value, TRUE);
              g_key_file_set_value (kfw->keyfile, group, key, printed);
              g_free (printed);
            }
          else
            g_key_file_remove_key (kfw->keyfile, group, key, NULL);

          g_free (group);
          g_free (key);
        }

      g_free (path);
    }
}

static gboolean
dconf_keyfile_writer_commit (DConfWriter  *writer,
                             GError      **error)
{
  DConfKeyfileWriter *kfw = (DConfKeyfileWriter *) writer;

  /* Pretty simple.  Write the keyfile. */
  {
    gchar *data;
    gsize size;

    /* docs say: "Note that this function never reports an error" */
    data = g_key_file_to_data (kfw->keyfile, &size, NULL);

    /* don't write it again if nothing changed */
    if (!kfw->contents || !g_str_equal (kfw->contents, data))
      {
        if (!g_file_set_contents (kfw->filename, data, size, error))
          {
            gchar *dirname;

            /* Maybe it failed because the directory doesn't exist.  Try
             * again, after mkdir().
             */
            dirname = g_path_get_dirname (kfw->filename);
            g_mkdir_with_parents (dirname, 0777);
            g_free (dirname);

            g_clear_error (error);
            if (!g_file_set_contents (kfw->filename, data, size, error))
              {
                g_free (data);
                return FALSE;
              }
          }
      }

    g_free (data);
  }

  /* Failing to update the shm file after writing the keyfile is
   * unlikely to occur.  It can only happen if the runtime dir hits
   * quota.
   *
   * If it does happen, we're in a bit of a bad spot because the on-disk
   * keyfile is now out-of-sync with the contents of the shm file.  We
   * fail the write because the apps will see the old values in the shm
   * file.
   *
   * Meanwhile we keep the on-disk keyfile as-is.  The next time we open
   * it we will notice that it's not in sync with the shm file and we'll
   * try to merge the two as if the changes were made by an outsider.
   * Eventually that may succeed... If it doesn't, what can we do?
   */
  return DCONF_WRITER_CLASS (dconf_keyfile_writer_parent_class)->commit (writer, error);
}

static void
dconf_keyfile_writer_end (DConfWriter *writer)
{
  DConfKeyfileWriter *kfw = (DConfKeyfileWriter *) writer;

  DCONF_WRITER_CLASS (dconf_keyfile_writer_parent_class)->end (writer);

  g_clear_pointer (&kfw->keyfile, g_key_file_free);
  g_clear_pointer (&kfw->contents, g_free);
  close (kfw->lock_fd);
  kfw->lock_fd = -1;
}

static gboolean
dconf_keyfile_update (gpointer user_data)
{
  DConfKeyfileWriter *kfw = user_data;

  if (dconf_keyfile_writer_begin (DCONF_WRITER (kfw), NULL))
    {
      dconf_keyfile_writer_commit (DCONF_WRITER (kfw), NULL);
      dconf_keyfile_writer_end (DCONF_WRITER (kfw));
    }

  kfw->scheduled_update = 0;

  return G_SOURCE_REMOVE;
}

static void
dconf_keyfile_writer_finalize (GObject *object)
{
  DConfKeyfileWriter *kfw = (DConfKeyfileWriter *) object;

  if (kfw->scheduled_update)
    g_source_remove (kfw->scheduled_update);

  g_clear_object (&kfw->monitor);
  g_free (kfw->lock_filename);
  g_free (kfw->filename);

  G_OBJECT_CLASS (dconf_keyfile_writer_parent_class)->finalize (object);
}

static void
dconf_keyfile_writer_init (DConfKeyfileWriter *kfw)
{
  dconf_writer_set_basepath (DCONF_WRITER (kfw), "keyfile");

  kfw->lock_fd = -1;
}

static void
dconf_keyfile_writer_class_init (DConfWriterClass *class)
{
  GObjectClass *object_class = G_OBJECT_CLASS (class);

  object_class->finalize = dconf_keyfile_writer_finalize;

  class->list = dconf_keyfile_writer_list;
  class->begin = dconf_keyfile_writer_begin;
  class->change = dconf_keyfile_writer_change;
  class->commit = dconf_keyfile_writer_commit;
  class->end = dconf_keyfile_writer_end;
}
