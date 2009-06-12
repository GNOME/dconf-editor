#include "dconf-core.h"

#include "dconf-reader.h"
#include "dconf-base.h"

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
        if (mount->dbs[i]->bus == NULL)
          mount->dbs[i]->bus = dconf_dbus_new (mount->dbs[i]->bus_name, NULL);
    }
}

static DConfMount *
dconf_demux_path (const gchar **path,
                  gboolean      rel)
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

  return NULL;
}

GVariant *
dconf_get (const gchar *key)
{
  GVariant *value = NULL;
  DConfMount *mount;

  mount = dconf_demux_path (&key, TRUE);

  if (mount)
    {
      gboolean locked = FALSE;
      gint i;

      for (i = mount->n_dbs; !locked && i >= 0; i--)
        dconf_reader_get (mount->dbs[i]->filename,
                          &mount->dbs[i]->reader,
                          key, &value, &locked);
    }

  return value;
}

/*
gchar **
dconf_list (const gchar *path,
            gint        *length)
{
  gchar **list;
  GTree *tree;

  g_print ("asking for '%s'\n", path);

  if (strcmp (path, "/") == 0)
    {
      if (length)
        *length = 3;

      return g_strsplit ("default/ user/ system/", " ", 3);
    }

  tree = g_tree_new_full ((GCompareDataFunc) strcmp, NULL, NULL, NULL);

  if (g_str_has_prefix (path, "/user/"))
    {
      gboolean locked = FALSE;

      dconf_reader_list (".d", &default_db, path + 6, tree, &locked);

      if (!locked)
        dconf_reader_list (".u", &user_db, path + 6, tree, &locked);
    }

  else if (g_str_has_prefix (path, "/system/"))
    dconf_reader_list (".s", &system_db, path + 8, tree, NULL);

  else if (g_str_has_prefix (path, "/default/"))
    dconf_reader_list (".d", &default_db, path + 8, tree, NULL);

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
*/

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

      mount = dconf_demux_path (&match, FALSE);

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

      mount = dconf_demux_path (&match, FALSE);

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
 * dconf_merge_tree:
 * @prefix: the common part of the path to write to
 * @tree: a list of the values to store
 * @sequence: a pointer for the sequence number return (or %NULL)
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
 * If the merge is successful then %TRUE will be returned.  If @sequence
 * is non-%NULL it will be set to the sequence number of the merge.  The
 * sequence number will be the same as the number that is sent for the
 * change notification corresponding to this modification.
 **/

/**
 * dconf_merge_tree_async:
 * @prefix: the common part of the path to write to
 * @values: a list of the values to store
 * @callback: the completion callback
 * @user_data: user data for @callback
 *
 * Atomically set the value of several keys.
 *
 * This is the asynchronous variant of dconf_merge_tree().  When the
 * merge is complete, @callback will be called with a #DConfAsyncResult
 * and @user_data.  You should pass the #DConfAsyncResult to
 * dconf_merge_finish() to collect the result.
 **/
void
dconf_merge_tree_async (const gchar             *prefix,
                        GTree                   *values,
                        DConfAsyncReadyCallback  callback,
                        gpointer                 user_data)
{
  DConfMount *mount;

  mount = dconf_demux_path (&prefix, TRUE);
  g_assert (mount);

  dconf_dbus_merge_tree_async (mount->dbs[0]->bus, prefix, values,
                               (DConfDBusAsyncReadyCallback) callback,
                               user_data);
}

/**
 * dconf_merge_tree:
 * @result: the #DConfAsyncResult given to your callback
 * @sequence: a pointer for the sequence number return (or %NULL)
 * @error: a pointer to a %NULL #GError pointer (or %NULL)
 * @returns: %TRUE on success
 *
 * Collects the results from a call to dconf_merge_tree_async() or
 * dconf_merge_array_async().
 *
 * This is the shared second half of the asyncronous variants of
 * dconf_merge_array() and dconf_merge_tree().
 **/
gboolean
dconf_merge_finish (DConfAsyncResult  *result,
                    guint32           *sequence,
                    GError           **error)
{
  return dconf_dbus_merge_finish ((DConfDBusAsyncResult *) result,
                                  sequence, error);
}
