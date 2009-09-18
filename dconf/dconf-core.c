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

#include "dconf.h"

#include "dconf-reader.h"

#include <string.h>
#include <glib.h>

#include "dconf-config.h"
#include "dconf-dbus.h"

static GSList *dconf_mounts;

static void
dconf_setup_mounts (void)
{
  GSList *node;

  dconf_mounts = dconf_config_read ();

  for (node = dconf_mounts; node; node = node->next)
    {
      DConfMount *mount = node->data;
      gint i;

      for (i = 0; i < mount->n_dbs; i++)
        {
          DConfDB *db = mount->dbs[i];

          if (db->bus == NULL)
            db->bus = dconf_dbus_new (db->bus_name, NULL);

          if (db->reader == NULL)
            db->reader = dconf_reader_new (db->filename);
        }
    }
}

static DConfMount *
dconf_demux_path (const gchar **path,
                  gboolean      rel,
                  GError      **error)
{
  GSList *node;

  if G_UNLIKELY (dconf_mounts == NULL)
    dconf_setup_mounts ();

  for (node = dconf_mounts; node; node = node->next)
    {
      DConfMount *mount = node->data;

      if (g_str_has_prefix (*path, mount->prefix))
        {
          if (rel)
            *path += strlen (mount->prefix);
          return mount;
        }
    }

  g_set_error (error, 0, 0,
               "the specified path is outside of any configuration database");

  return NULL;
}

/**
 * dconf_get:
 * @key: a dconf key
 * @returns: a #GVariant, or %NULL
 *
 * Lookup a key in dconf.
 *
 * If the key exists, it is returned.  If the key does not exist then
 * %NULL is returned.
 *
 * dconf doesn't really have errors when reading keys.  If, for example,
 * the configuration database file does not exist then it is equivalent
 * to being empty (ie: %NULL will always be returned).
 *
 * It is a programmer error to call this function with a @key that is
 * not a valid dconf key (as per dconf_is_key()).
 **/
GVariant *
dconf_get (const gchar *key)
{
  GVariant *value = NULL;
  DConfMount *mount;

  mount = dconf_demux_path (&key, TRUE, NULL);

  if (mount)
    {
      gboolean locked = FALSE;
      gint i;

      for (i = mount->n_dbs - 1; !locked && i >= 0; i--)
        dconf_reader_get (mount->dbs[i]->reader,
                          key, &value, &locked);
    }

  return value;
}

static gboolean
append_to_array (gpointer               key,
                 G_GNUC_UNUSED gpointer value,
                 gpointer               data)
{
  *((*(gchar ***) data)++) = g_strdup ((gchar *) key);
  return FALSE;
}

/**
 * dconf_list:
 * @path: a dconf path
 * @length: a pointer to the length of the return value
 * @returns: a %NULL-terminated list of strings
 *
 * Get a list of sub-items directly below a given path in dconf.
 *
 * Directory existence in dconf is not strong -- that is, directories
 * exist only to hold keys.  There is no distinction between an "empty
 * directory" and a directory that does not exist.  For this reason,
 * this function will always return a list -- it may simply be empty.
 *
 * Additionally, dconf doesn't really have errors when reading keys.
 * If, for example, the configuration database file does not exist then
 * it is equivalent to being empty (ie: the empty list will always be
 * returned).
 *
 * If @length is non-%NULL then it will be set to the length of the
 * return array, excluding the %NULL.
 *
 * It is appropriate to free the return value using g_strfreev().
 *
 * It is a programmer error to call this function with a @path that is
 * not a valid dconf path (as per dconf_is_path()).
 **/
gchar **
dconf_list (const gchar *path,
            gint        *length)
{
  g_assert (dconf_is_path (path));

  if (path[1] == '\0') /* '/' */
    {
      GSList *node;
      gchar **list;
      gint mounts;

      if G_UNLIKELY (dconf_mounts == NULL)
        dconf_setup_mounts ();

      mounts = 0;
      for (node = dconf_mounts; node; node = node->next)
        mounts++;

      list = g_new (gchar *, mounts + 1);
      mounts = 0;

      for (node = dconf_mounts; node; node = node->next)
        {
          DConfMount *mount = node->data;

          list[mounts++] = g_strdup (mount->prefix + 1);
        }

      list[mounts] = NULL;

      if (length)
        *length = mounts;

      return list;
    }
  else
    {
      DConfMount *mount;
      gchar **list;
      GTree *tree;

      tree = g_tree_new_full ((GCompareDataFunc) strcmp,
                              NULL, g_free, NULL);

      mount = dconf_demux_path (&path, TRUE, NULL);

      if (mount)
        {
          gboolean locked = FALSE;
          gint i;

          for (i = mount->n_dbs - 1; !locked && i >= 0; i--)
            dconf_reader_list (mount->dbs[i]->reader, path, tree, &locked);
        }

      list = g_new (gchar *, g_tree_nnodes (tree) + 1);

      {
        gchar **ptr = list;
        g_tree_foreach (tree, append_to_array, &ptr);
        *ptr = NULL;
      }

      if (length)
        *length = g_tree_nnodes (tree);

      g_tree_destroy (tree);

      return list;
   }
}

/**
 * dconf_get_locked:
 * @path: a dconf key or path
 * @returns: %TRUE if @path is locked
 *
 * Checks if a lock exists at the current position in the tree.  This
 * call is the exact dual of dconf_set_locked(); the return value here
 * is exactly equal to what was last set with dconf_set_locked() on the
 * exact same @path.
 *
 * This is the value you would show in a lockdown editor for it a lock
 * exists at the current point.
 *
 * If the path doesn't exist in the tree then %FALSE is returned.
 *
 * This result of this function is not impacted by locks installed in
 * 'default' databases -- only those in the toplevel database that the
 * user would modify by calling dconf_set_locked().  It is also not
 * impacted by entire-directory locks installed at higher points in the
 * tree.  See dconf_get_writable() if you are interested in that.
 *
 * It is a programmer error to call this function with a @path that is
 * not a valid dconf path (as per dconf_is_path()) or key (as per
 * dconf_is_key()).
 **/
gboolean
dconf_get_locked (const gchar *path)
{
  gboolean locked = FALSE;
  DConfMount *mount;

  mount = dconf_demux_path (&path, TRUE, NULL);
  if (mount && mount->n_dbs)
    locked = dconf_reader_get_locked (mount->dbs[0]->reader, path);

  return locked;
}

/**
 * dconf_get_writable:
 * @path: a dconf key or path
 * @returns: %TRUE if writing to @path would work
 *
 * Checks if writing to a given @path would work.  For a key to be
 * writable, it may not be locked in any database nor may any of its
 * parents.
 *
 * This is the value you would use to determine if a settings widget
 * should be displayed in a UI as sensitive.
 *
 * If the path doesn't exist in the tree then %FALSE is returned.
 *
 * It is a programmer error to call this function with a @path that is
 * not a valid dconf path (as per dconf_is_path()) or key (as per
 * dconf_is_key()).
 **/
gboolean
dconf_get_writable (const gchar *path)
{
  gboolean writable = TRUE;
  DConfMount *mount;

  mount = dconf_demux_path (&path, TRUE, NULL);
  if (mount)
    {
      gint i;

      for (i = mount->n_dbs - 1; writable && i >= 0; i--)
        writable = dconf_reader_get_writable (mount->dbs[i]->reader, path);
    }

  return writable;
}

/**
 * dconf_watch:
 * @match: a key or path to watch
 * @callback: a #DConfWatchFunc
 * @user_data: user data for @callback
 *
 * Watch part of the database for changes.
 *
 * If @match ends with a '/' then any key that changes under the path
 * given by @match will result in @callback being called.
 *
 * If @match does not end with a '/' then the key exactly specified by
 * @match will result in @callback being called.
 *
 * You will currently get spurious callbacks.  This will be fixed.
 **/
void
dconf_watch (const gchar    *match,
             DConfWatchFunc  callback,
             gpointer        user_data)
{
  if G_UNLIKELY (dconf_mounts == NULL)
    dconf_setup_mounts ();

  if (strcmp (match, "/") == 0)
    {
      GSList *node;

      for (node = dconf_mounts; node; node = node->next)
        {
          DConfMount *mount = node->data;
          gint i;

          for (i = 0; i < mount->n_dbs; i++)
            dconf_dbus_watch (mount->dbs[i]->bus, mount->prefix,
                              callback, user_data);
        }
    }
  else
    {
      DConfMount *mount;

      mount = dconf_demux_path (&match, FALSE, NULL);

      if (mount)
        {
          gint i;

          for (i = 0; i < mount->n_dbs; i++)
            dconf_dbus_watch (mount->dbs[i]->bus, match,
                              callback, user_data);
        }
    }
}

/**
 * dconf_unwatch:
 * @match: the exact key or path given to dconf_watch()
 * @callback: the exact callback given to dconf_watch()
 * @user_data: the exact user data given to dconf_watch()
 *
 * Removes an existing watch.  The given arguments must exactly match
 * the ones given to an earlier call to dconf_watch() (@callback and
 * @user_data must be identical; @match need only be equal by value).
 *
 * In the event that more than one watch was registered with the same
 * values then this call removes only one of them.
 **/
void
dconf_unwatch (const gchar    *match,
               DConfWatchFunc  callback,
               gpointer        user_data)
{
  if G_UNLIKELY (dconf_mounts == NULL)
    dconf_setup_mounts ();

  if (strcmp (match, "/") == 0)
    {
      GSList *node;

      for (node = dconf_mounts; node; node = node->next)
        {
          DConfMount *mount = node->data;
          gint i;

          for (i = 0; i < mount->n_dbs; i++)
            dconf_dbus_unwatch (mount->dbs[i]->bus, mount->prefix,
                                callback, user_data);
        }
    }
  else
    {
      DConfMount *mount;

      mount = dconf_demux_path (&match, FALSE, NULL);

      if (mount)
        {
          gint i;

          for (i = 0; i < mount->n_dbs; i++)
            dconf_dbus_unwatch (mount->dbs[i]->bus, match,
                                callback, user_data);
        }
    }
}

/**
 * dconf_merge:
 * @prefix: the common part of the path to write to
 * @tree: a list of the values to store
 * @event_id: a pointer for the event ID return (or %NULL)
 * @error: a pointer to a %NULL #GError pointer (or %NULL)
 * @returns: %TRUE on success
 *
 * Atomically set the value of several keys.  This is a "merge" in the
 * sense that the values in @tree are merged into the existing
 * configuration database at @prefix.
 *
 * @tree should be a #GTree created by a call to dconf_tree_new().
 *
 * There are two ways to use this call.
 *
 * In the simple case for setting the value of a single key, @prefix
 * should be equal to the path of the key to set and @tree should
 * contain a single entry: a key of "" and a value of the #GVariant
 * value to set at @prefix.
 *
 * In the case of setting more than one key, @prefix should be equal to
 * the largest common prefix of the key shared by each of the keys to be
 * set (up to and including the nearest '/').  Each key in @tree should
 * then be a path relative to this common prefix and each corresponding
 * value should be the #GVariant value to store at that path.
 *
 * It is not an error to call this function with a @prefix that is not
 * the largest it could possibly be.  It is also not an error to call
 * this function with @prefix being a path and @tree containing a single
 * item with a key that is not equal to "".  Using a @prefix that is not
 * specific to a single backend database (ie: specifying '/') is an
 * error, however, and using shorter prefixes will generally result in
 * unnecessary wakeups (for example, using a prefix of '/user/' will
 * result in waking up every process watching for any change
 * notification anywhere within '/user/').
 *
 * In the event of a failure of any kind then no changes will be made to
 * the database, %error (if non-%NULL) will be set and %FALSE will be
 * returned.
 *
 * If the merge is successful then %TRUE will be returned.  If @event_id
 * is non-%NULL it will be set to the event ID number of the merge.  The
 * event ID will be the same as the ID that is sent for the change
 * notification corresponding to this modification and is unique for the
 * life of the program.  It has no particular format.
 **/
gboolean
dconf_merge (const gchar  *prefix,
             GTree        *tree,
             gchar       **event_id,
             GError      **error)
{
  DConfMount *mount;

  g_assert (prefix != NULL);
  g_assert (tree != NULL);

  g_assert (g_str_has_suffix (prefix, "/") || g_tree_nnodes (tree) == 1);
  g_assert (g_str_has_prefix (prefix, "/"));

  mount = dconf_demux_path (&prefix, TRUE, NULL);
  g_assert (mount);

  return dconf_dbus_merge (mount->dbs[0]->bus, prefix, tree, event_id, error);
}

/**
 * dconf_merge_async:
 * @prefix: the common part of the path to write to
 * @values: a list of the values to store
 * @callback: the completion callback
 * @user_data: user data for @callback
 *
 * Atomically set the value of several keys.
 *
 * This is the asynchronous variant of dconf_merge().  When the merge is
 * complete, @callback will be called with a #DConfAsyncResult and
 * @user_data.  You should pass the #DConfAsyncResult to
 * dconf_merge_finish() to collect the result.
 **/
void
dconf_merge_async (const gchar             *prefix,
                   GTree                   *tree,
                   DConfAsyncReadyCallback  callback,
                   gpointer                 user_data)
{
  DConfMount *mount;

  g_assert (prefix != NULL);
  g_assert (tree != NULL);

  g_assert (g_str_has_suffix (prefix, "/") || g_tree_nnodes (tree) == 1);
  g_assert (g_str_has_prefix (prefix, "/"));

  mount = dconf_demux_path (&prefix, TRUE, NULL);
  g_assert (mount);

  dconf_dbus_merge_async (mount->dbs[0]->bus, prefix, tree,
                          (DConfDBusAsyncReadyCallback) callback,
                          user_data);
}

/**
 * dconf_merge_finish:
 * @result: the #DConfAsyncResult given to your callback
 * @event_id: a pointer for the event ID return (or %NULL)
 * @error: a pointer to a %NULL #GError pointer (or %NULL)
 * @returns: %TRUE on success
 *
 * Collects the results from a call to dconf_merge_async().
 *
 * This is the second half of the asyncronous variant of dconf_merge().
 **/
gboolean
dconf_merge_finish (DConfAsyncResult  *result,
                    gchar            **event_id,
                    GError           **error)
{
  return dconf_dbus_async_finish ((DConfDBusAsyncResult *) result,
                                  "u", event_id, error);
}

gboolean
dconf_set (const gchar  *key,
           GVariant     *value,
           gchar       **event_id,
           GError      **error)
{
  DConfMount *mount;

  g_assert (dconf_is_key (key));
  g_assert (value != NULL);

  if ((mount = dconf_demux_path (&key, TRUE, error)) == NULL)
    return FALSE;

  return dconf_dbus_set (mount->dbs[0]->bus, key, value, event_id, error);
}

void
dconf_set_async (const gchar             *key,
                 GVariant                *value,
                 DConfAsyncReadyCallback  callback,
                 gpointer                 user_data)
{
  DConfMount *mount;

  g_assert (dconf_is_key (key));
  g_assert (value != NULL);

  mount = dconf_demux_path (&key, TRUE, NULL);
  g_assert (mount);

  dconf_dbus_set_async (mount->dbs[0]->bus, key, value,
                        (DConfDBusAsyncReadyCallback) callback,
                        user_data);
}

gboolean
dconf_set_finish (DConfAsyncResult  *result,
                  gchar            **event_id,
                  GError           **error)
{
  return dconf_dbus_async_finish ((DConfDBusAsyncResult *) result,
                                  "u", event_id, error);
}

gboolean
dconf_reset (const gchar  *key,
             gchar       **event_id,
             GError      **error)
{
  DConfMount *mount;

  g_assert (dconf_is_key (key) || dconf_is_path (key));

  if ((mount = dconf_demux_path (&key, TRUE, error)) == NULL)
    return FALSE;

  return dconf_dbus_reset (mount->dbs[0]->bus, key, event_id, error);
}

void
dconf_reset_async (const gchar             *key,
                   DConfAsyncReadyCallback  callback,
                   gpointer                 user_data)
{
  DConfMount *mount;

  g_assert (dconf_is_key (key));

  mount = dconf_demux_path (&key, TRUE, NULL);
  g_assert (mount);

  dconf_dbus_reset_async (mount->dbs[0]->bus, key,
                          (DConfDBusAsyncReadyCallback) callback,
                          user_data);
}

gboolean
dconf_reset_finish (DConfAsyncResult  *result,
                    gchar            **event_id,
                    GError           **error)
{
  return dconf_dbus_async_finish ((DConfDBusAsyncResult *) result,
                                  "u", event_id, error);
}

gboolean
dconf_set_locked (const gchar  *key,
                  gboolean      locked,
                  GError      **error)
{
  DConfMount *mount;

  g_assert (dconf_is_key (key));

  if ((mount = dconf_demux_path (&key, TRUE, error)) == NULL)
    return FALSE;

  return dconf_dbus_set_locked (mount->dbs[0]->bus, key, !!locked, error);
}

void
dconf_set_locked_async (const gchar             *key,
                        gboolean                 locked,
                        DConfAsyncReadyCallback  callback,
                        gpointer                 user_data)
{
  DConfMount *mount;

  g_assert (dconf_is_key (key));

  mount = dconf_demux_path (&key, TRUE, NULL);
  g_assert (mount);

  dconf_dbus_set_locked_async (mount->dbs[0]->bus, key, !!locked,
                               (DConfDBusAsyncReadyCallback) callback,
                               user_data);
}

gboolean
dconf_set_locked_finish (DConfAsyncResult  *result,
                         GError           **error)
{
  return dconf_dbus_async_finish ((DConfDBusAsyncResult *) result,
                                  "", NULL, error);
}
