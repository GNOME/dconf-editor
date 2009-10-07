/*
 * Copyright © 2007, 2008  Ryan Lortie
 * Copyright © 2009  Codethink Limited
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

/**
 * dconf_is_key:
 * @key: a possible key
 * @Returns: %TRUE if @key is valid
 *
 * Determines if @key is a valid key.
 *
 * A key is valid if it starts with a slash, does
 * not end with a slash, and contains no two
 * consecutive slashes.  A key is different from a
 * path in that it does not end with "/".
 **/
gboolean
dconf_is_key (const char *key)
{
  int i;

  if (key == NULL)
    return FALSE;

  if (key[0] != '/')
    return FALSE;

  for (i = 0; key[i]; i++)
    if (key[i] == '/' && key[i + 1] == '/')
      return FALSE;

  return key[i - 1] != '/';
}

/**
 * dconf_is_path:
 * @path: a possible path
 * @Returns: %TRUE if @path is valid
 *
 * Determines if @path is a valid key for use with
 * the dconf_list() function.
 *
 * A path is valid if it starts with a slash, ends
 * with a slash and contains no two consecutive
 * slashes.  A path is different from a key in
 * that it ends with "/".
 *
 * "/" is a valid path.
 **/
gboolean
dconf_is_path (const char *path)
{
  int i;

  if (path == NULL)
    return FALSE;

  if (path[0] != '/')
    return FALSE;

  for (i = 0; path[i]; i++)
    if (path[i] == '/' && path[i+1] == '/')
      return FALSE;

  return path[i - 1] == '/';
}

/**
 * dconf_is_key_or_path:
 * @key_or_path: a possible key or path
 * @Returns: %TRUE if @key_or_path is valid
 *
 * Determines if @key_or_path is a valid key or path.
 **/
gboolean
dconf_is_key_or_path (const gchar *key_or_path)
{
  int i;

  if (key_or_path == NULL)
    return FALSE;

  if (key_or_path[0] != '/')
    return FALSE;

  for (i = 0; key_or_path[i]; i++)
    if (key_or_path[i] == '/' && key_or_path[i + 1] == '/')
      return FALSE;

  return TRUE;
}

/**
 * dconf_match:
 * @key_or_path1: a dconf key or path
 * @key_or_path2: a dconf key or path
 * @Returns: %TRUE iff @key_or_path1 matches @key_or_path2
 *
 * Checks if @key_or_path1 matches @key_or_path2.
 *
 * Match is a symmetric predicate on a pair of strings defined as
 * follows: two strings match if and only if they are exactly equal or
 * one of them ends with a slash and is a prefix of the other.
 *
 * The match predicate is of significance in two parts of the dconf API.
 *
 * First, when registering watches for change notifications, any key
 * that matches the requested watch will be reported.  This means that
 * if your watch string ends with a slash then changes to any key that
 * has the watch string as the initial part of its path will be
 * reported.
 *
 * Second, any lock set on the database will restrict write access to
 * any key that matches the lock.  This means that if your lock string
 * ends with a slash then no key that has the lock string as it prefix
 * may be written to.
 **/
gboolean
dconf_match (const char *key_or_path1,
             const char *key_or_path2)
{
  int length1, length2;

  length1 = strlen (key_or_path1);
  length2 = strlen (key_or_path2);

  if (length1 < length2 && key_or_path1[length1 - 1] != '/')
    return FALSE;

  if (length2 < length1 && key_or_path2[length2 - 1] != '/')
    return FALSE;

  return memcmp (key_or_path1, key_or_path2, MIN (length1, length2)) == 0;
}

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
            *path += strlen (mount->prefix) - 1;
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

  g_return_val_if_fail (dconf_is_key (key), NULL);

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
  g_return_val_if_fail (dconf_is_path (path), NULL);

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
 * @key_or_path: a dconf key or path
 * @returns: %TRUE if @key_or_path is locked
 *
 * Checks if a lock exists at the current position in the tree.  This
 * call is the exact dual of dconf_set_locked(); the return value here
 * is exactly equal to what was last set with dconf_set_locked() on the
 * exact same @key_or_path.
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
 * It is a programmer error to call this function with a @key_or_path
 * that is not a valid dconf path (as per dconf_is_path()) or key (as
 * per dconf_is_key()).
 **/
gboolean
dconf_get_locked (const gchar *key_or_path)
{
  gboolean locked = FALSE;
  DConfMount *mount;

  g_return_val_if_fail (dconf_is_key_or_path (key_or_path), FALSE);

  mount = dconf_demux_path (&key_or_path, TRUE, NULL);
  if (mount && mount->n_dbs)
    locked = dconf_reader_get_locked (mount->dbs[0]->reader, key_or_path);

  return locked;
}

/**
 * dconf_get_writable:
 * @key_or_path: a dconf key or path
 * @returns: %TRUE if writing to @key_or_path would work
 *
 * Checks if writing to a given @key_or_path would work.  For a key to
 * be writable, it may not be locked in any database nor may any of its
 * parents.
 *
 * This is the value you would use to determine if a settings widget
 * should be displayed in a UI as sensitive.
 *
 * If the path doesn't exist in the tree then %FALSE is returned.
 *
 * It is a programmer error to call this function with a @key_or_path
 * that is not a valid dconf path (as per dconf_is_path()) or key (as
 * per dconf_is_key()).
 **/
gboolean
dconf_get_writable (const gchar *key_or_path)
{
  gboolean writable = TRUE;
  DConfMount *mount;

  g_return_val_if_fail (dconf_is_key_or_path (key_or_path), FALSE);

  mount = dconf_demux_path (&key_or_path, TRUE, NULL);
  if (mount)
    {
      gint i;

      for (i = mount->n_dbs - 1; writable && i >= 0; i--)
        writable = dconf_reader_get_writable (mount->dbs[i]->reader,
                                              key_or_path);
    }

  return writable;
}

static gboolean
dconf_check_writable (DConfMount   *mount,
                      const gchar  *key,
                      GError      **error)
{
  gboolean writable = TRUE;
  gint i;

  for (i = 0; writable && i < mount->n_dbs; i++)
    writable = dconf_reader_get_writable (mount->dbs[i]->reader, key);

  if (!writable)
    {
      g_set_error (error, 0, 0,
                   "this key is locked");
    }

  return writable;
}


static gboolean
dconf_check_tree_writable (DConfMount   *mount,
                           const gchar  *prefix,
                           GTree        *tree,
                           GError      **error)
{
  const gchar * const *const_items;
  gboolean writable = TRUE;
  gchar **items;
  gint length;
  gint i;

  length = g_tree_nnodes (tree);
  items = g_new (gchar *, length + 1);
  const_items = (const gchar * const *) items;

  {
    gchar **ptr = items;
    g_tree_foreach (tree, append_to_array, &ptr);
    *ptr = NULL;
  }

  for (i = 0; writable && i < mount->n_dbs; i++)
    writable = dconf_reader_get_several_writable (mount->dbs[i]->reader,
                                                  prefix, const_items);
  g_strfreev (items);

  if (!writable)
    {
      g_set_error (error, 0, 0,
                   "one or more keys are locked");
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
 * @user_data must be identical; @match need only be equal by string
 * comparison).
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
 * @event_id: a pointer for the event ID return, or %NULL
 * @error: a pointer to a %NULL #GError pointer, or %NULL
 * @returns: %TRUE on success
 *
 * Atomically set the value of several keys in the dconf database.
 *
 * This is a "merge" in the sense that the values in @tree are merged
 * into the existing configuration database at @prefix.
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

  g_return_val_if_fail (prefix != NULL, FALSE);
  g_return_val_if_fail (tree != NULL, FALSE);
  g_return_val_if_fail (g_str_has_suffix (prefix, "/") ||
                        g_tree_nnodes (tree) == 1, FALSE);
  g_return_val_if_fail (g_str_has_prefix (prefix, "/"), FALSE);
  g_return_val_if_fail (g_tree_nnodes (tree) > 0, FALSE);
  g_return_val_if_fail (error == NULL || *error == NULL, FALSE);

  if ((mount = dconf_demux_path (&prefix, TRUE, error)) == NULL)
    return FALSE;

  if (!dconf_check_tree_writable (mount, prefix, tree, error))
    return FALSE;

  return dconf_dbus_merge (mount->dbs[0]->bus, prefix, tree, event_id, error);
}

/**
 * dconf_merge_async:
 * @prefix: the common part of the path to write to
 * @values: a list of the values to store
 * @callback: the completion callback
 * @user_data: user data for @callback
 *
 * Atomically set the value of several keys in the dconf database.
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
  GError *error = NULL;
  DConfMount *mount;

  g_return_if_fail (prefix != NULL);
  g_return_if_fail (tree != NULL);
  g_return_if_fail (g_str_has_suffix (prefix, "/") ||
                        g_tree_nnodes (tree) == 1);
  g_return_if_fail (g_str_has_prefix (prefix, "/"));
  g_return_if_fail (g_tree_nnodes (tree) > 0);


  if ((mount = dconf_demux_path (&prefix, TRUE, &error)) == NULL ||
      !dconf_check_tree_writable (mount, prefix, tree, &error))
    {
      dconf_dbus_dispatch_error ((DConfDBusAsyncReadyCallback) callback,
                                 user_data, error);
      g_error_free (error);
      return;
    }

  dconf_dbus_merge_async (mount->dbs[0]->bus, prefix, tree,
                          (DConfDBusAsyncReadyCallback) callback,
                          user_data);
}

/**
 * dconf_merge_finish:
 * @result: the #DConfAsyncResult given to your callback
 * @event_id: a pointer for the event ID return, or %NULL
 * @error: a pointer to a %NULL #GError pointer, or %NULL
 * @returns: %TRUE on success
 *
 * Collects the results from a call to dconf_merge_async().
 *
 * This is the second half of the asynchronous variant of dconf_merge().
 **/
gboolean
dconf_merge_finish (DConfAsyncResult  *result,
                    gchar            **event_id,
                    GError           **error)
{
  g_return_val_if_fail (result != NULL, FALSE);
  g_return_val_if_fail (error == NULL || *error == NULL, FALSE);

  return dconf_dbus_async_finish ((DConfDBusAsyncResult *) result,
                                  "u", event_id, error);
}

/**
 * dconf_set:
 * @key: a dconf key
 * @value: a #GVariant, which will be sunk
 * @event_id: a pointer for the event ID return, or %NULL
 * @error: a pointer to a %NULL #GError pointer, or %NULL
 *
 * Sets the value of a key in the dconf database.
 *
 * If @value has a floating reference, it will be consumed by this call.
 *
 * @value may not be %NULL.  If you wish to reset the value of a key,
 * then use dconf_reset().
 *
 * In the event of a failure of any kind then no changes will be made to
 * the database, %error (if non-%NULL) will be set and %FALSE will be
 * returned.
 *
 * If the set is successful then %TRUE will be returned.  If @event_id
 * is non-%NULL it will be set to the event ID number of the merge.  The
 * event ID will be the same as the ID that is sent for the change
 * notification corresponding to this modification and is unique for the
 * life of the program.  It has no particular format.
 *
 * It is a programmer error to call this function with a @key that is
 * not a valid dconf key (as per dconf_is_key()).
 **/
gboolean
dconf_set (const gchar  *key,
           GVariant     *value,
           gchar       **event_id,
           GError      **error)
{
  DConfMount *mount;

  g_return_val_if_fail (dconf_is_key (key), FALSE);
  g_return_val_if_fail (value != NULL, FALSE);
  g_return_val_if_fail (error == NULL || *error == NULL, FALSE);

  if ((mount = dconf_demux_path (&key, TRUE, error)) == NULL)
    return FALSE;

  if (!dconf_check_writable (mount, key, error))
    return FALSE;

  return dconf_dbus_set (mount->dbs[0]->bus, key, value, event_id, error);
}

/**
 * dconf_set_async:
 * @key: a dconf key
 * @value: a #GVariant, on which g_variant_ref_sink() will be called
 * @callback: the completion callback
 * @user_data: user data for @callback
 *
 * Sets the value of a key in the dconf database.
 *
 * This is the asynchronous variant of dconf_set().  When the merge is
 * complete, @callback will be called with a #DConfAsyncResult and
 * @user_data.  You should pass the #DConfAsyncResult to
 * dconf_set_finish() to collect the result.
 **/
void
dconf_set_async (const gchar             *key,
                 GVariant                *value,
                 DConfAsyncReadyCallback  callback,
                 gpointer                 user_data)
{
  GError *error = NULL;
  DConfMount *mount;

  g_return_if_fail (dconf_is_key (key));
  g_return_if_fail (value != NULL);

  if ((mount = dconf_demux_path (&key, TRUE, &error)) == NULL ||
      !dconf_check_writable (mount, key, &error))
    {
      dconf_dbus_dispatch_error ((DConfDBusAsyncReadyCallback) callback,
                                 user_data, error);
      g_error_free (error);
      return;
    }

  dconf_dbus_set_async (mount->dbs[0]->bus, key, value,
                        (DConfDBusAsyncReadyCallback) callback,
                        user_data);
}

/**
 * dconf_set_finish:
 * @result: the #DConfAsyncResult given to your callback
 * @event_id: a pointer for the event ID return, or %NULL
 * @error: a pointer to a %NULL #GError pointer, or %NULL
 * @returns: %TRUE on success
 *
 * Collects the results from a call to dconf_set_async().
 *
 * This is the second half of the asynchronous variant of dconf_set().
 **/
gboolean
dconf_set_finish (DConfAsyncResult  *result,
                  gchar            **event_id,
                  GError           **error)
{
  g_return_val_if_fail (error == NULL || *error == NULL, FALSE);

  return dconf_dbus_async_finish ((DConfDBusAsyncResult *) result,
                                  "u", event_id, error);
}

/**
 * dconf_reset:
 * @key: a dconf key
 * @event_id: a pointer for the event ID return, or %NULL
 * @error: a pointer to a %NULL #GError pointer, or %NULL
 *
 * Resets the value of a key in the dconf database.
 *
 * This unsets the value in the toplevel database.  This will either
 * result in the key no longer existing, or it reverting to a default
 * value (as specified in a lower-level database).
 *
 * In the event of a failure of any kind then no changes will be made to
 * the database, %error (if non-%NULL) will be set and %FALSE will be
 * returned.
 *
 * If the reset is successful then %TRUE will be returned.  If @event_id
 * is non-%NULL it will be set to the event ID number of the merge.  The
 * event ID will be the same as the ID that is sent for the change
 * notification corresponding to this modification and is unique for the
 * life of the program.  It has no particular format.
 *
 * It is a programmer error to call this function with a @key that is
 * not a valid dconf key (as per dconf_is_key()).
 **/
gboolean
dconf_reset (const gchar  *key,
             gchar       **event_id,
             GError      **error)
{
  DConfMount *mount;

  g_return_val_if_fail (dconf_is_key (key), FALSE);
  g_return_val_if_fail (error == NULL || *error == NULL, FALSE);

  if ((mount = dconf_demux_path (&key, TRUE, error)) == NULL)
    return FALSE;

  return dconf_dbus_reset (mount->dbs[0]->bus, key, event_id, error);
}

/**
 * dconf_reset_async:
 * @key: a dconf key
 * @callback: the completion callback
 * @user_data: user data for @callback
 *
 * Resets the value of a key in the dconf database.
 *
 * This is the asynchronous variant of dconf_reset().  When the merge is
 * complete, @callback will be called with a #DConfAsyncResult and
 * @user_data.  You should pass the #DConfAsyncResult to
 * dconf_reset_finish() to collect the result.
 **/
void
dconf_reset_async (const gchar             *key,
                   DConfAsyncReadyCallback  callback,
                   gpointer                 user_data)
{
  GError *error = NULL;
  DConfMount *mount;

  g_return_if_fail (dconf_is_key (key));

  if ((mount = dconf_demux_path (&key, TRUE, &error)) == NULL)
    {
      dconf_dbus_dispatch_error ((DConfDBusAsyncReadyCallback) callback,
                                 user_data, error);
      g_error_free (error);
      return;
    }

  dconf_dbus_reset_async (mount->dbs[0]->bus, key,
                          (DConfDBusAsyncReadyCallback) callback,
                          user_data);
}

/**
 * dconf_reset_finish:
 * @result: the #DConfAsyncResult given to your callback
 * @event_id: a pointer for the event ID return, or %NULL
 * @error: a pointer to a %NULL #GError pointer, or %NULL
 * @returns: %TRUE on success
 *
 * Collects the results from a call to dconf_reset_async().
 *
 * This is the second half of the asynchronous variant of dconf_reset().
 **/
gboolean
dconf_reset_finish (DConfAsyncResult  *result,
                    gchar            **event_id,
                    GError           **error)
{
  g_return_val_if_fail (error == NULL || *error == NULL, FALSE);

  return dconf_dbus_async_finish ((DConfDBusAsyncResult *) result,
                                  "u", event_id, error);
}

/**
 * dconf_set_locked:
 * @key_or_path: a dconf key or path
 * @error: a pointer to a %NULL #GError pointer, or %NULL
 *
 * Locks or unlocks a key or path in the dconf database.
 *
 * This marks a given key or set of keys in the dconf database as
 * locked.  Writes will be prevented to any key that is locked or is
 * contained inside of a path that is locked.
 *
 * If the operation is successful then %TRUE will be returned.  In the
 * event of a failure of any kind then no changes will be made to the
 * database, %error (if non-%NULL) will be set and %FALSE will be
 * returned.
 *
 * It is a programmer error to call this function with a @key_or_path
 * that is not a valid dconf path (as per dconf_is_path()) or key (as
 * per dconf_is_key()).
 **/
gboolean
dconf_set_locked (const gchar  *key_or_path,
                  gboolean      locked,
                  GError      **error)
{
  DConfMount *mount;

  g_return_val_if_fail (dconf_is_key_or_path (key_or_path), FALSE);
  g_return_val_if_fail (error == NULL || *error == NULL, FALSE);

  if ((mount = dconf_demux_path (&key_or_path, TRUE, error)) == NULL)
    return FALSE;

  return dconf_dbus_set_locked (mount->dbs[0]->bus,
                                key_or_path,
                                !!locked, error);
}

/**
 * dconf_set_locked_async:
 * @key_or_path: a dconf key or path
 * @callback: the completion callback
 * @user_data: user data for @callback
 *
 * Locks or unlocks a key or path in the dconf database.
 *
 * This is the asynchronous variant of dconf_set_locked().  When the
 * operation is complete, @callback will be called with a
 * #DConfAsyncResult and @user_data.  You should pass the
 * #DConfAsyncResult to dconf_set_locked_finish() to collect the result.
 **/
void
dconf_set_locked_async (const gchar             *key_or_path,
                        gboolean                 locked,
                        DConfAsyncReadyCallback  callback,
                        gpointer                 user_data)
{
  GError *error = NULL;
  DConfMount *mount;

  g_return_if_fail (dconf_is_key_or_path (key_or_path));

  if ((mount = dconf_demux_path (&key_or_path, TRUE, &error)) == NULL)
    {
      dconf_dbus_dispatch_error ((DConfDBusAsyncReadyCallback) callback,
                                 user_data, error);
      g_error_free (error);
      return;
    }

  dconf_dbus_set_locked_async (mount->dbs[0]->bus, key_or_path, !!locked,
                               (DConfDBusAsyncReadyCallback) callback,
                               user_data);
}

/**
 * dconf_set_locked_finish:
 * @result: the #DConfAsyncResult given to your callback
 * @error: a pointer to a %NULL #GError pointer, or %NULL
 * @returns: %TRUE on success
 *
 * Collects the results from a call to dconf_set_locked_async().
 *
 * This is the second half of the asynchronous variant of
 * dconf_set_locked().
 **/
gboolean
dconf_set_locked_finish (DConfAsyncResult  *result,
                         GError           **error)
{
  g_return_val_if_fail (error == NULL || *error == NULL, FALSE);

  return dconf_dbus_async_finish ((DConfDBusAsyncResult *) result,
                                  "", NULL, error);
}
