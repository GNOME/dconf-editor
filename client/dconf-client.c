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

#include "dconf-client.h"

#include "../engine/dconf-engine.h"
#include <glib-object.h>

/**
 * SECTION:client
 * @title: DConfClient
 * @short_description: Direct read and write access to dconf, based on GDBus
 *
 * This is the primary client interface to dconf.
 *
 * It allows applications to directly read from and write to the dconf
 * database.  Applications can subscribe to change notifications.
 *
 * Most applications probably don't want to access dconf directly and
 * would be better off using something like #GSettings.
 *
 * Please note that the API of libdconf is not stable in any way.  It
 * has changed in incompatible ways in the past and there will be
 * further changes in the future.
 **/

/**
 * DConfClient:
 *
 * The main object for interacting with dconf.  This is a #GObject, so
 * you should manage it with g_object_ref() and g_object_unref().
 **/
struct _DConfClient
{
  GObject parent_instance;

  DConfEngine  *engine;
  GMainContext *context;
};

G_DEFINE_TYPE (DConfClient, dconf_client, G_TYPE_OBJECT)

enum
{
  SIGNAL_CHANGED,
  N_SIGNALS
};
static guint dconf_client_signals[N_SIGNALS];

static void
dconf_client_finalize (GObject *object)
{
  DConfClient *client = DCONF_CLIENT (object);

  dconf_engine_unref (client->engine);
  g_main_context_unref (client->context);

  G_OBJECT_CLASS (dconf_client_parent_class)
    ->finalize (object);
}

static void
dconf_client_init (DConfClient *client)
{
}

static void
dconf_client_class_init (DConfClientClass *class)
{
  class->finalize = dconf_client_finalize;

  /**
   * DConfClient::changed:
   * @client: the #DConfClient reporting the change
   * @prefix: the prefix under which the changes happened
   * @changes: the list of paths that were changed, relative to @prefix
   * @tag: the tag for the change, if it originated from the service
   *
   * This signal is emitted when the #DConfClient has a possible change
   * to report.  The signal is an indication that a change may have
   * occurred; it's possible that the keys will still have the same value
   * as before.
   *
   * To ensure that you receive notification about changes to paths that
   * you are interested in you must call dconf_client_watch_fast() or
   * dconf_client_watch_sync().  You may still receive notifications for
   * paths that you did not explicitly watch.
   *
   * @prefix will be an absolute dconf path; see dconf_is_path().
   * @changes is a %NULL-terminated array of dconf rel paths; see
   * dconf_is_rel_path().
   *
   * @tag is an opaque tag string, or %NULL.  The only thing you should
   * do with @tag is to compare it to tag values returned by
   * dconf_client_write_sync() or dconf_client_change_sync().
   *
   * The number of changes being reported is equal to the length of
   * @changes.  Appending each item in @changes to @prefix will give the
   * absolute path of each changed item.
   *
   * If a single key has changed then @prefix will be equal to the key
   * and @changes will contain a single item: the empty string.
   *
   * If a single dir has changed (indicating that any key under the dir
   * may have changed) then @prefix will be equal to the dir and
   * @changes will contain a single empty string.
   *
   * If more than one change is being reported then @changes will have
   * more than one item.
   **/
  dconf_client_signals[SIGNAL_CHANGED] = g_signal_new ("changed", DCONF_TYPE_CLIENT, G_SIGNAL_RUN_LAST,
                                                       0, NULL, NULL, NULL, G_TYPE_NONE, 3,
                                                       G_TYPE_STRING | G_SIGNAL_TYPE_STATIC_SCOPE,
                                                       G_TYPE_STRV | G_SIGNAL_TYPE_STATIC_SCOPE,
                                                       G_TYPE_STRING | G_SIGNAL_TYPE_STATIC_SCOPE);
}

typedef struct
{
  DConfClient  *client;
  gchar        *prefix;
  gchar       **changes;
  gchar        *tag;
} DConfClientChange;

static gboolean
dconf_client_dispatch_change_signal (gpointer user_data)
{
  DConfClientChange *change = user_data;

  g_signal_emit (change->client, dconf_client_signals[SIGNAL_CHANGED], 0,
                 change->prefix, change->changes, change->tag);

  g_object_unref (change->client);
  g_free (change->prefix);
  g_strfreev (change->changes);
  g_free (change->tag);
  g_slice_free (DConfClientChange, change);

  return G_SOURCE_REMOVE;
}

void
dconf_engine_change_notify (DConfEngine         *engine,
                            const gchar         *prefix,
                            const gchar * const *changes,
                            const gchar *        tag,
                            gpointer             origin_tag,
                            gpointer             user_data)
{
  GWeakRef *weak_ref = user_data;
  DConfClientChange *change;
  DConfClient *client;

  client = g_weak_ref_get (weak_ref);

  if (client == NULL)
    return;

  g_return_if_fail (DCONF_IS_CLIENT (client));

  change = g_slice_new (DConfClientChange);
  change->client = client;
  change->prefix = g_strdup (prefix);
  change->changes = g_strdupv ((gchar **) changes);
  change->tag = g_strdup (tag);

  g_main_context_invoke (client->context, dconf_client_dispatch_change_signal, change);
}

static void
dconf_client_free_weak_ref (gpointer data)
{
  GWeakRef *weak_ref = data;

  g_weak_ref_clear (weak_ref);
  g_slice_free (GWeakRef, weak_ref);
}

/**
 * dconf_client_new:
 *
 * Creates a new #DConfClient.
 *
 * Returns: a new #DConfClient
 **/
DConfClient *
dconf_client_new (void)
{
  DConfClient *client;
  GWeakRef *weak_ref;

  client = g_object_new (DCONF_TYPE_CLIENT, NULL);
  weak_ref = g_slice_new (GWeakRef);
  g_weak_ref_init (weak_ref, client);
  client->engine = dconf_engine_new (weak_ref, dconf_client_free_weak_ref);
  client->context = g_main_context_ref_thread_default ();

  return client;
}

/**
 * dconf_client_read:
 * @client: a #DConfClient
 * @key: the key to read the value of
 *
 * Reads the current value of @key.
 *
 * If @key exists, its value is returned.  Otherwise, %NULL is returned.
 *
 * If there are outstanding "fast" changes in progress they may affect
 * the result of this call.
 *
 * Returns: a #GVariant, or %NULL
 **/
GVariant *
dconf_client_read (DConfClient *client,
                   const gchar *key)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), NULL);

  return dconf_engine_read (client->engine, NULL, key);
}

/**
 * dconf_client_list:
 * @client: a #DConfClient
 * @dir: the dir to list the contents of
 * @length: the length of the returned list
 *
 * Gets the list of all dirs and keys immediately under @dir.
 *
 * If @length is non-%NULL then it will be set to the length of the
 * returned array.  In any case, the array is %NULL-terminated.
 *
 * IF there are outstanding "fast" changes in progress then this call
 * may return inaccurate results with respect to those outstanding
 * changes.
 *
 * Returns: an array of strings, never %NULL.
 **/
gchar **
dconf_client_list (DConfClient *client,
                   const gchar *dir,
                   gint        *length)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), NULL);

  return dconf_engine_list (client->engine, dir, length);
}

/**
 * dconf_client_is_writable:
 * @client: a #DConfClient
 * @key: the key to check for writability
 *
 * Checks if @key is writable (ie: the key has no locks).
 *
 * This call does not verify that writing to the key will actually be
 * successful.  It only checks that the database is writable and that
 * there are no locks affecting @key.  Other issues (such as a full disk
 * or an inability to connect to the bus and start the service) may
 * cause the write to fail.
 *
 * Returns: %TRUE is @key is writable
 **/
gboolean
dconf_client_is_writable (DConfClient *client,
                          const gchar *key)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  return dconf_engine_is_writable (client->engine, key);
}

/**
 * dconf_client_write_fast:
 * @client: a #DConfClient
 * @key: the key to write to
 * @value: a #GVariant, the value to write
 * @error: a pointer to a %NULL #GError, or %NULL
 *
 * Writes @value to the given @key, or reset @key to its default value.
 *
 * If @value is %NULL then @key is reset to its default value (which may
 * be completely unset), otherwise @value becomes the new value.
 *
 * This call merely queues up the write and returns immediately, without
 * blocking.  The only errors that can be detected or reported at this
 * point are attempts to write to read-only keys.  If the application
 * exits immediately after this function returns then the queued call
 * may never be sent; see dconf_client_sync().
 *
 * A local copy of the written value is kept so that calls to
 * dconf_client_read() that occur before the service actually makes the
 * change will return the new value.
 *
 * If the write is queued then a change signal will be directly emitted.
 * If this function is being called from the main context of @client
 * then the signal is emitted before this function returns; otherwise it
 * is scheduled on the main context.
 *
 * Returns: %TRUE if the write was queued
 **/
gboolean
dconf_client_write_fast (DConfClient  *client,
                         const gchar  *key,
                         GVariant     *value,
                         GError      **error)
{
  DConfChangeset *changeset;
  gboolean success;

  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  changeset = dconf_changeset_new_write (key, value);
  success = dconf_engine_change_fast (client->engine, changeset, NULL, error);
  dconf_changeset_unref (changeset);

  return success;
}

/**
 * dconf_client_write_sync:
 * @client: a #DConfClient
 * @key: the key to write to
 * @value: a #GVariant, the value to write
 * @tag: (out) (allow-none): the tag from this write
 * @cancellable: a #GCancellable, or %NULL
 * @error: a pointer to a %NULL #GError, or %NULL
 *
 * Write @value to the given @key, or reset @key to its default value.
 *
 * If @value is %NULL then @key is reset to its default value (which may
 * be completely unset), otherwise @value becomes the new value.
 *
 * This call blocks until the write is complete.  This call will
 * therefore detect and report all cases of failure.  If the modified
 * key is currently being watched then a signal will be emitted from the
 * main context of @client (once the signal arrives from the service).
 *
 * If @tag is non-%NULL then it is set to the unique tag associated with
 * this write.  This is the same tag that will appear in the following
 * change signal.
 *
 * Returns: %TRUE on success, else %FALSE with @error set
 **/
gboolean
dconf_client_write_sync (DConfClient   *client,
                         const gchar   *key,
                         GVariant      *value,
                         gchar        **tag,
                         GCancellable  *cancellable,
                         GError       **error)
{
  DConfChangeset *changeset;
  gboolean success;

  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  changeset = dconf_changeset_new_write (key, value);
  success = dconf_engine_change_sync (client->engine, changeset, tag, error);
  dconf_changeset_unref (changeset);

  return success;
}

/**
 * dconf_client_change_fast:
 * @client: a #DConfClient
 * @changeset: the changeset describing the requested change
 * @error: a pointer to a %NULL #GError, or %NULL
 *
 * Performs the change operation described by @changeset.
 *
 * Once @changeset is passed to this call it can no longer be modified.
 *
 * This call merely queues up the write and returns immediately, without
 * blocking.  The only errors that can be detected or reported at this
 * point are attempts to write to read-only keys.  If the application
 * exits immediately after this function returns then the queued call
 * may never be sent; see dconf_client_sync().
 *
 * A local copy of the written value is kept so that calls to
 * dconf_client_read() that occur before the service actually makes the
 * change will return the new value.
 *
 * If the write is queued then a change signal will be directly emitted.
 * If this function is being called from the main context of @client
 * then the signal is emitted before this function returns; otherwise it
 * is scheduled on the main context.
 *
 * Returns: %TRUE if the requested changed was queued
 **/
gboolean
dconf_client_change_fast (DConfClient     *client,
                          DConfChangeset  *changeset,
                          GError         **error)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  return dconf_engine_change_fast (client->engine, changeset, NULL, error);
}

/**
 * dconf_client_change_sync:
 * @client: a #DConfClient
 * @changeset: the changeset describing the requested change
 * @tag: (out) (allow-none): the tag from this write
 * @cancellable: a #GCancellable, or %NULL
 * @error: a pointer to a %NULL #GError, or %NULL
 *
 * Performs the change operation described by @changeset.
 *
 * Once @changeset is passed to this call it can no longer be modified.
 *
 * This call blocks until the change is complete.  This call will
 * therefore detect and report all cases of failure.  If any of the
 * modified keys are currently being watched then a signal will be
 * emitted from the main context of @client (once the signal arrives
 * from the service).
 *
 * If @tag is non-%NULL then it is set to the unique tag associated with
 * this change.  This is the same tag that will appear in the following
 * change signal.  If @changeset makes no changes then @tag may be
 * non-unique (eg: the empty string may be used for empty changesets).
 *
 * Returns: %TRUE on success, else %FALSE with @error set
 **/
gboolean
dconf_client_change_sync (DConfClient     *client,
                          DConfChangeset  *changeset,
                          gchar          **tag,
                          GCancellable    *cancellable,
                          GError         **error)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  return dconf_engine_change_sync (client->engine, changeset, tag, error);
}

/**
 * dconf_client_watch_fast:
 * @client: a #DConfClient
 * @path: a path to watch
 *
 * Requests change notifications for @path.
 *
 * If @path is a key then the single key is monitored.  If @path is a
 * dir then all keys under the dir are monitored.
 *
 * This function queues the watch request with D-Bus and returns
 * immediately.  There is a very slim chance that the dconf database
 * could change before the watch is actually established.  If that is
 * the case then a synthetic change signal will be emitted.
 *
 * Errors are silently ignored.
 **/
void
dconf_client_watch_fast (DConfClient *client,
                         const gchar *path)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_watch_fast (client->engine, path);
}

/**
 * dconf_client_watch_sync:
 * @client: a #DConfClient
 * @path: a path to watch
 *
 * Requests change notifications for @path.
 *
 * If @path is a key then the single key is monitored.  If @path is a
 * dir then all keys under the dir are monitored.
 *
 * This function submits each of the various watch requests that are
 * required to monitor a key and waits until each of them returns.  By
 * the time this function returns, the watch has been established.
 *
 * Errors are silently ignored.
 **/
void
dconf_client_watch_sync (DConfClient *client,
                         const gchar *path)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_watch_sync (client->engine, path);
}

/**
 * dconf_client_unwatch_fast:
 * @client: a #DConfClient
 * @path: a path previously watched
 *
 * Cancels the effect of a previous call to dconf_client_watch_fast().
 *
 * This call returns immediately.
 *
 * It is still possible that change signals are received after this call
 * had returned (watching guarantees notification of changes, but
 * unwatching does not guarantee no notifications).
 **/
void
dconf_client_unwatch_fast (DConfClient *client,
                           const gchar *path)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_unwatch_fast (client->engine, path);
}

/**
 * dconf_client_unwatch_sync:
 * @client: a #DConfClient
 * @path: a path previously watched
 *
 * Cancels the effect of a previous call to dconf_client_watch_sync().
 *
 * This function submits each of the various unwatch requests and waits
 * until each of them returns.  It is still possible that change signals
 * are received after this call has returned (watching guarantees
 * notification of changes, but unwatching does not guarantee no
 * notifications).
 **/
void
dconf_client_unwatch_sync (DConfClient *client,
                           const gchar *path)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_unwatch_sync (client->engine, path);
}

/**
 * dconf_client_sync:
 * @client: a #DConfClient
 *
 * Blocks until all outstanding "fast" change or write operations have
 * been submitted to the service.
 *
 * Applications should generally call this before exiting on any
 * #DConfClient that they wrote to.
 **/
void
dconf_client_sync (DConfClient *client)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_sync (client->engine);
}
