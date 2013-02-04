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

#define _XOPEN_SOURCE 600
#include "dconf-engine.h"

#include "../gvdb/gvdb-reader.h"
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#include "dconf-engine-profile.h"

/* The engine has zero or more sources.
 *
 * If it has zero sources then things are very uninteresting.  Nothing
 * is writable, nothing will ever be written and reads will always
 * return NULL.
 *
 * There are two interesting cases when there is a non-zero number of
 * sources.  Writing only ever occurs to the first source, if at all.
 * Non-first sources are never writable.
 *
 * The first source may or may not be writable.  In the usual case the
 * first source is the one in the user's home directory and is writable,
 * but it may be that the profile was setup for read-only access to
 * system sources only.
 *
 * In the case that the first source is not writable (and therefore
 * there are no writable sources), is_writable() will always return
 * FALSE and no writes will ever be performed.
 *
 * It's possible to request changes in three ways:
 *
 *  - synchronous: the D-Bus message is immediately sent to the
 *    dconf service and we block until we receive the reply.  The change
 *    signal will follow soon thereafter (when we receive the signal on
 *    D-Bus).
 *
 *  - asynchronous: typical asynchronous operation: we send the request
 *    and return immediately, notifying using a callback when the
 *    request is completed (and the new value is in the database).  The
 *    change signal follows in the same way as with synchronous.
 *
 *  - fast: we record the value locally and signal the change, returning
 *    immediately, as if the value is already in the database (from the
 *    viewpoint of the local process).  We keep note of the new value
 *    locally until the service has confirmed that the write was
 *    successful.  If the write fails, we emit a change signal.  From
 *    the view of the program it looks like the value was successfully
 *    changed but then quickly changed back again by some external
 *    agent.
 *
 * In fast mode we have to do some management of the queue.  If we
 * immediately put all requests "in flight" then we can end up in a
 * situation where the application writes many values for the same key
 * and the service is kept (needlessly) busy writing over and over to
 * the same key for some time after the requests stop coming in.
 *
 * If we limit the number of in-flight requests and put the other ones
 * into a pending queue then we can perform merging of similar changes.
 * If we notice that an item in the pending queue writes to the same
 * keys as the newly-added request then we can simply drop the existing
 * request (since its effect will be nullified by the new request).
 *
 * We want to keep the number of in-flight requests low in order to
 * maximise our chance of dropping pending items, but we probably want
 * it higher than 1 so that we can pipeline to hide latency.
 *
 * In order to minimise complexity, all changes go first to the pending
 * queue.  Changes are dispatched from the pending queue (and moved to
 * the in-flight queue) when the number of requests in-flight is lower
 * than the maximum.
 *
 * For both 'in_flight' and 'pending' queues we push to the tail and pop
 * from the head.  This puts the first operation on the head and the
 * most recent operation on the tail.
 *
 * Since new operation go first to the pending queue, we find the most
 * recent operations at the tail of that queue.  Since we want to return
 * the most-recently written value, we therefore scan for values
 * starting at the tail of the pending queue and ending at the head of
 * the in-flight queue.
 *
 * NB: I tell a lie.  Async is not supported yet.
 *
 * Notes about threading:
 *
 * The engine is oblivious to threads and main contexts.
 *
 * What this means is that the engine has no interaction with GMainLoop
 * and will not schedule idles or anything of the sort.  All calls made
 * by the engine to the client library will be made in response to
 * incoming method calls, from the same thread as the incoming call.
 *
 * If dconf_engine_call_handle_reply() or
 * dconf_engine_handle_dbus_signal() are called from 'exotic' threads
 * (as will often be the case) then the resulting calls to
 * dconf_engine_change_notify() will come from the same thread.  That's
 * left for the client library to deal with.
 *
 * All that said, the engine is completely threadsafe.  The client
 * library can call any method from any thread at any time -- as long as
 * it is willing to deal with receiving the change notifies in those
 * threads.
 *
 * Thread-safety is implemented using two locks.
 *
 * The first lock (sources_lock) protects the sources.  Although the
 * sources are only ever read from, it is necessary to lock them because
 * it is not safe to read during a refresh (when the source is being
 * closed and reopened).  Accordingly, sources_lock need only be
 * acquired when accessing the parts of the sources that are subject to
 * change as a result of refreshes; the static parts (like bus type,
 * object path, etc) can be accessed without holding the lock.  The
 * 'sources' array itself (and 'n_sources') are set at construction and
 * never change after that.
 *
 * The second lock (queue_lock) protects the various queues that are
 * used to implement the "fast" writes described above.
 *
 * If both locks are held at the same time then the sources lock must
 * have been acquired first.
 */

#define MAX_IN_FLIGHT 2

static GSList *dconf_engine_global_list;
static GMutex  dconf_engine_global_lock;

struct _DConfEngine
{
  gpointer            user_data;    /* Set at construct time */
  GDestroyNotify      free_func;
  gint                ref_count;

  GMutex              sources_lock; /* This lock is for the sources (ie: refreshing) and state. */
  guint64             state;        /* Counter that changes every time a source is refreshed. */
  DConfEngineSource **sources;      /* Array never changes, but each source changes internally. */
  gint                n_sources;

  GMutex              queue_lock;   /* This lock is for pending, in_flight, queue_cond */
  GCond               queue_cond;   /* Signalled when the queues empty */
  GQueue              pending;      /* DConfChangeset */
  GQueue              in_flight;    /* DConfChangeset */

  gchar              *last_handled; /* reply tag from last item in in_flight */
};

/* When taking the sources lock we check if any of the databases have
 * had updates.
 *
 * Anything that is accessing the database (even only reading) needs to
 * be holding the lock (since refreshes could be happening in another
 * thread), so this makes sense.
 *
 * We could probably optimise this to avoid checking some databases in
 * certain cases (ie: we do not need to check the user's database when
 * we are only interested in checking writability) but this works well
 * enough for now and is less prone to errors.
 *
 * We could probably change to a reader/writer situation that is only
 * holding the write lock when actually making changes during a refresh
 * but the engine is probably only ever really in use by two threads at
 * a given time (main thread doing reads, DBus worker thread clearing
 * the queue) so it seems unlikely that lock contention will become an
 * issue.
 *
 * If it does, we can revisit this...
 */
static void
dconf_engine_acquire_sources (DConfEngine *engine)
{
  gint i;

  g_mutex_lock (&engine->sources_lock);

  for (i = 0; i < engine->n_sources; i++)
    if (dconf_engine_source_refresh (engine->sources[i]))
      engine->state++;
}

static void
dconf_engine_release_sources (DConfEngine *engine)
{
  g_mutex_unlock (&engine->sources_lock);
}

static void
dconf_engine_lock_queues (DConfEngine *engine)
{
  g_mutex_lock (&engine->queue_lock);
}

static void
dconf_engine_unlock_queues (DConfEngine *engine)
{
  g_mutex_unlock (&engine->queue_lock);
}

DConfEngine *
dconf_engine_new (gpointer       user_data,
                  GDestroyNotify free_func)
{
  DConfEngine *engine;

  engine = g_slice_new0 (DConfEngine);
  engine->user_data = user_data;
  engine->free_func = free_func;
  engine->ref_count = 1;

  g_mutex_init (&engine->sources_lock);
  g_mutex_init (&engine->queue_lock);
  g_cond_init (&engine->queue_cond);

  engine->sources = dconf_engine_profile_open (NULL, &engine->n_sources);

  g_mutex_lock (&dconf_engine_global_lock);
  dconf_engine_global_list = g_slist_prepend (dconf_engine_global_list, engine);
  g_mutex_unlock (&dconf_engine_global_lock);

  return engine;
}

void
dconf_engine_unref (DConfEngine *engine)
{
  gint ref_count;

 again:
  ref_count = engine->ref_count;

  if (ref_count == 1)
    {
      gint i;

      /* We are about to drop the last reference, but there is a chance
       * that a signal may be happening at this very moment, causing the
       * engine to gain another reference (due to its position in the
       * global engine list).
       *
       * Acquiring the lock here means that either we will remove this
       * engine from the list first or we will notice the reference
       * count has increased (and skip the free).
       */
      g_mutex_lock (&dconf_engine_global_lock);
      if (engine->ref_count != 1)
        {
          g_mutex_unlock (&dconf_engine_global_lock);
          goto again;
        }
      dconf_engine_global_list = g_slist_remove (dconf_engine_global_list, engine);
      g_mutex_unlock (&dconf_engine_global_lock);

      g_mutex_clear (&engine->sources_lock);
      g_mutex_clear (&engine->queue_lock);
      g_cond_clear (&engine->queue_cond);

      g_free (engine->last_handled);

      for (i = 0; i < engine->n_sources; i++)
        dconf_engine_source_free (engine->sources[i]);

      g_free (engine->sources);

      if (engine->free_func)
        engine->free_func (engine->user_data);

      g_slice_free (DConfEngine, engine);
    }

  else if (!g_atomic_int_compare_and_exchange (&engine->ref_count, ref_count, ref_count - 1))
    goto again;
}

static DConfEngine *
dconf_engine_ref (DConfEngine *engine)
{
  g_atomic_int_inc (&engine->ref_count);

  return engine;
}

guint64
dconf_engine_get_state (DConfEngine *engine)
{
  guint64 state;

  dconf_engine_acquire_sources (engine);
  state = engine->state;
  dconf_engine_release_sources (engine);

  return state;
}

static gboolean
dconf_engine_is_writable_internal (DConfEngine *engine,
                                   const gchar *key)
{
  gint i;

  /* We must check several things:
   *
   *  - we have at least one source
   *
   *  - the first source is writable
   *
   *  - the key is not locked in a non-writable (ie: non-first) source
   */
  if (engine->n_sources == 0)
    return FALSE;

  if (engine->sources[0]->writable == FALSE)
    return FALSE;

  /* Ignore locks in the first source.
   *
   * Either it is writable and therefore ignoring locks is the right
   * thing to do, or it's non-writable and we caught that case above.
   */
  for (i = 1; i < engine->n_sources; i++)
    if (engine->sources[i]->locks && gvdb_table_has_value (engine->sources[i]->locks, key))
      return FALSE;

  return TRUE;
}

gboolean
dconf_engine_is_writable (DConfEngine *engine,
                          const gchar *key)
{
  gboolean writable;

  dconf_engine_acquire_sources (engine);
  writable = dconf_engine_is_writable_internal (engine, key);
  dconf_engine_release_sources (engine);

  return writable;
}

static gboolean
dconf_engine_find_key_in_queue (GQueue       *queue,
                                const gchar  *key,
                                GVariant    **value)
{
  GList *node;

  /* Tail to head... */
  for (node = g_queue_peek_tail_link (queue); node; node = node->prev)
    if (dconf_changeset_get (node->data, key, value))
      return TRUE;

  return FALSE;
}

GVariant *
dconf_engine_read (DConfEngine *engine,
                   GQueue      *read_through,
                   const gchar *key)
{
  GVariant *value = NULL;
  gint lock_level = 0;
  gint i;

  dconf_engine_acquire_sources (engine);

  /* There are a number of situations that this function has to deal
   * with and they interact in unusual ways.  We attempt to write the
   * rules for all cases here:
   *
   * With respect to the steady-state condition with no locks:
   *
   *   This is the case where there are no changes queued, no
   *   read_through and no locks.
   *
   *   The value returned is the one from the lowest-index source that
   *   contains that value.
   *
   * With respect to locks:
   *
   *   If a lock is present (except in source #0 where it is ignored)
   *   then we will only return a value found in the source where the
   *   lock was present, or a higher-index source (following the normal
   *   rule that sources with lower indexes take priority).
   *
   *   This statement includes read_through and queued changes.  If a
   *   lock is found, we will ignore those.
   *
   * With respect to read_through and queued changed:
   *
   *   We only consider read_through and queued changes in the event
   *   that we have a writable source.  This will possibly cause us to
   *   ignore read_through and will have no real effect on the queues
   *   (since they will be empty anyway if we have no writable source).
   *
   *   We only consider read_through and queued changes in the event
   *   that we have not found any locks.
   *
   *   If there is a non-NULL value found in read_through or the queued
   *   changes then we will return that value.
   *
   *   If there is a NULL value (ie: a reset) found in read_through or
   *   the queued changes then we will only ignore any value found in
   *   the first source (which must be writable, or else we would not
   *   have been considering read_through and the queues).  This is
   *   consistent with the fact that a reset will unset any value found
   *   in this source but will not affect values found in lower sources.
   *
   *   Put another way: if a non-writable source contains a value for a
   *   particular key then it is impossible for this function to return
   *   NULL.
   *
   * We implement the above rules as follows.  We have three state
   * tracking variables:
   *
   *   - lock_level: records if and where we found a lock
   *
   *   - found_key: records if we found the key in any queue
   *
   *   - value: records the value of the found key (NULL for resets)
   *
   * We take these steps:
   *
   *  1. check for lockdown.  If we find a lock then we prevent any
   *     other sources (including read_through and pending/in-flight)
   *     from affecting the value of the key.
   *
   *     We record the result of this in the lock_level variable.  Zero
   *     means that no locks were found.  Non-zero means that a lock was
   *     found in the source with the index given by the variable.
   *
   *  2. check the uncommitted changes in the read_through list as the
   *     highest priority.  This is only done if we have a writable
   *     source and no locks were found.
   *
   *     If we found an entry in the read_through then we set
   *     'found_key' to TRUE and set 'value' to the value that we found
   *     (which will be NULL in the case of finding a reset request).
   *
   *  3. check our pending and in-flight "fast" changes (in that order).
   *     This is only done if we have a writable source and no locks
   *     were found.  It is also only done if we did not find the key in
   *     the read_through.
   *
   *  4. check the first source, if there is one.
   *
   *     This is only done if 'found_key' is FALSE.  If 'found_key' is
   *     TRUE then it means that the first database was writable and we
   *     either found a value that will replace it (value != NULL) or
   *     found a pending reset (value == NULL) that will unset it.
   *
   *     We only actually do this step if we have a writable first
   *     source and no locks found, otherwise we just let step 5 do all
   *     the checking.
   *
   *  5. check the remaining sources.
   *
   *     We do this until we have value != NULL.  Even if found_key was
   *     TRUE, the reset that was requested will not have affected the
   *     lower-level databases.
   */

  /* Step 1.  Check for locks.
   *
   * Note: i > 0 (strictly).  Ignore locks for source #0.
   */
  for (i = engine->n_sources - 1; i > 0; i--)
    if (engine->sources[i]->locks && gvdb_table_has_value (engine->sources[i]->locks, key))
      {
        lock_level = i;
        break;
      }

  /* Only do steps 2 to 4 if we have no locks and we have a writable source. */
  if (!lock_level && engine->n_sources != 0 && engine->sources[0]->writable)
    {
      gboolean found_key = FALSE;

      /* Step 2.  Check read_through. */
      if (read_through)
        found_key = dconf_engine_find_key_in_queue (read_through, key, &value);

      /* Step 3.  Check queued changes if we didn't find it in read_through.
       *
       * NB: We may want to optimise this to avoid taking the lock in
       * the case that we know both queues are empty.
       */
      if (!found_key)
        {
          dconf_engine_lock_queues (engine);

          /* Check the pending queue first because those were submitted
           * more recently.
           */
          found_key = dconf_engine_find_key_in_queue (&engine->pending, key, &value) ||
                      dconf_engine_find_key_in_queue (&engine->in_flight, key, &value);

          dconf_engine_unlock_queues (engine);
        }

      /* Step 4.  Check the first source. */
      if (!found_key && engine->sources[0]->values)
        value = gvdb_table_get_value (engine->sources[0]->values, key);

      /* We already checked source #0 (or ignored it, as appropriate).
       *
       * Abuse the lock_level variable to get step 5 to skip this one.
       */
      lock_level = 1;
    }

  /* Step 5.  Check the remaining sources, until value != NULL. */
  for (i = lock_level; value == NULL && i < engine->n_sources; i++)
    {
      if (engine->sources[i]->values == NULL)
        continue;

      if ((value = gvdb_table_get_value (engine->sources[i]->values, key)))
        break;
    }

  dconf_engine_release_sources (engine);

  return value;
}

gchar **
dconf_engine_list (DConfEngine *engine,
                   const gchar *dir,
                   gint        *length)
{
  GHashTable *results;
  GHashTableIter iter;
  gchar **list;
  gint n_items;
  gpointer key;
  gint i;

  /* This function is unreliable in the presence of pending changes.
   * Here's why:
   *
   * Consider the case that we list("/a/") and a pending request has a
   * reset request recorded for "/a/b/c".  The question of if "b/"
   * should appear in the output rests on if "/a/b/d" also exists.
   *
   * Put another way: If "/a/b/c" is the only key in "/a/b/" then
   * resetting it would mean that "/a/b/" stops existing (and we should
   * not include it in the output).  If there are others keys then it
   * will continue to exist and we should include it.
   *
   * Instead of trying to sort this out, we just ignore the pending
   * requests and report what the on-disk file says.
   */

  results = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);

  dconf_engine_acquire_sources (engine);

  for (i = 0; i < engine->n_sources; i++)
    {
      gchar **partial_list;
      gint j;

      if (engine->sources[i]->values == NULL)
        continue;

      partial_list = gvdb_table_list (engine->sources[i]->values, dir);

      if (partial_list != NULL)
        {
          for (j = 0; partial_list[j]; j++)
            /* Steal the keys from the list. */
            g_hash_table_add (results, partial_list[j]);

          /* Free only the list. */
          g_free (partial_list);
        }
    }

  dconf_engine_release_sources (engine);

  n_items = g_hash_table_size (results);
  list = g_new (gchar *, n_items + 1);

  i = 0;
  g_hash_table_iter_init (&iter, results);
  while (g_hash_table_iter_next (&iter, &key, NULL))
    {
      g_hash_table_iter_steal (&iter);
      list[i++] = key;
    }
  list[i] = NULL;
  g_assert_cmpint (i, ==, n_items);

  if (length)
    *length = n_items;

  g_hash_table_unref (results);

  return list;
}

typedef void (* DConfEngineCallHandleCallback) (DConfEngine  *engine,
                                                gpointer      handle,
                                                GVariant     *parameter,
                                                const GError *error);

struct _DConfEngineCallHandle
{
  DConfEngine                   *engine;
  DConfEngineCallHandleCallback  callback;
  const GVariantType            *expected_reply;
};

static gpointer
dconf_engine_call_handle_new (DConfEngine                   *engine,
                              DConfEngineCallHandleCallback  callback,
                              const GVariantType            *expected_reply,
                              gsize                          size)
{
  DConfEngineCallHandle *handle;

  g_assert (engine != NULL);
  g_assert (callback != NULL);
  g_assert (size >= sizeof (DConfEngineCallHandle));

  handle = g_malloc0 (size);
  handle->engine = dconf_engine_ref (engine);
  handle->callback = callback;
  handle->expected_reply = expected_reply;

  return handle;
}

const GVariantType *
dconf_engine_call_handle_get_expected_type (DConfEngineCallHandle *handle)
{
  return handle->expected_reply;
}

void
dconf_engine_call_handle_reply (DConfEngineCallHandle *handle,
                                GVariant              *parameter,
                                const GError          *error)
{
  if (handle == NULL)
    return;

  (* handle->callback) (handle->engine, handle, parameter, error);
}

static void
dconf_engine_call_handle_free (DConfEngineCallHandle *handle)
{
  dconf_engine_unref (handle->engine);
  g_free (handle);
}

/* returns floating */
static GVariant *
dconf_engine_make_match_rule (DConfEngineSource *source,
                              const gchar       *path)
{
  GVariant *params;
  gchar *rule;

  rule = g_strdup_printf ("type='signal',"
                          "interface='ca.desrt.dconf.Writer',"
                          "path='%s',"
                          "arg0path='%s'",
                          source->object_path,
                          path);

  params = g_variant_new ("(s)", rule);

  g_free (rule);

  return params;
}

typedef struct
{
  DConfEngineCallHandle handle;

  guint64 state;
  gint    pending;
} OutstandingWatch;

static void
dconf_engine_watch_established (DConfEngine  *engine,
                                gpointer      handle,
                                GVariant     *reply,
                                const GError *error)
{
  OutstandingWatch *ow = handle;

  /* ignore errors */

  if (--ow->pending)
    /* more on the way... */
    return;

  if (ow->state != dconf_engine_get_state (engine))
    {
      const gchar * const changes[] = { "", NULL };

      /* Our recorded state does not match the current state.  Something
       * must have changed while our watch requests were on the wire.
       *
       * We don't know what changed, so we can just say that potentially
       * everything changed.  This case is very rare, anyway...
       */
      dconf_engine_change_notify (engine, "/", changes, NULL, NULL, engine->user_data);
    }

  dconf_engine_call_handle_free (handle);
}

void
dconf_engine_watch_fast (DConfEngine *engine,
                         const gchar *path)
{
  OutstandingWatch *ow;
  gint i;

  if (engine->n_sources == 0)
    return;

  /* It's possible (although rare) that the dconf database could change
   * while our match rule is on the wire.
   *
   * Since we returned immediately (suggesting to the user that the
   * watch was already established) we could have a race.
   *
   * To deal with this, we use the current state counter to ensure that nothing
   * changes while the watch requests are on the wire.
   */
  ow = dconf_engine_call_handle_new (engine, dconf_engine_watch_established,
                                     G_VARIANT_TYPE_UNIT, sizeof (OutstandingWatch));
  ow->state = dconf_engine_get_state (engine);
  ow->pending = engine->n_sources;

  for (i = 0; i < engine->n_sources; i++)
    dconf_engine_dbus_call_async_func (engine->sources[i]->bus_type, "org.freedesktop.DBus",
                                       "/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch",
                                       dconf_engine_make_match_rule (engine->sources[i], path),
                                       &ow->handle, NULL);
}

void
dconf_engine_unwatch_fast (DConfEngine *engine,
                           const gchar *path)
{
  gint i;

  for (i = 0; i < engine->n_sources; i++)
    dconf_engine_dbus_call_async_func (engine->sources[i]->bus_type, "org.freedesktop.DBus",
                                       "/org/freedesktop/DBus", "org.freedesktop.DBus", "RemoveMatch",
                                       dconf_engine_make_match_rule (engine->sources[i], path), NULL, NULL);
}

static void
dconf_engine_handle_match_rule_sync (DConfEngine *engine,
                                     const gchar *method_name,
                                     const gchar *path)
{
  gint i;

  /* We need not hold any locks here because we are only touching static
   * things: the number of sources, and static properties of each source
   * itself.
   *
   * This function silently ignores all errors.
   */

  for (i = 0; i < engine->n_sources; i++)
    {
      GVariant *result;

      result = dconf_engine_dbus_call_sync_func (engine->sources[i]->bus_type, "org.freedesktop.DBus",
                                                 "/org/freedesktop/DBus", "org.freedesktop.DBus", method_name,
                                                 dconf_engine_make_match_rule (engine->sources[i], path),
                                                 G_VARIANT_TYPE_UNIT, NULL);

      if (result)
        g_variant_unref (result);
    }
}

void
dconf_engine_watch_sync (DConfEngine *engine,
                         const gchar *path)
{
  dconf_engine_handle_match_rule_sync (engine, "AddMatch", path);
}

void
dconf_engine_unwatch_sync (DConfEngine *engine,
                           const gchar *path)
{
  dconf_engine_handle_match_rule_sync (engine, "RemoveMatch", path);
}

typedef struct
{
  DConfEngineCallHandle handle;

  DConfChangeset *change;
} OutstandingChange;

static GVariant *
dconf_engine_prepare_change (DConfEngine     *engine,
                             DConfChangeset  *change)
{
  GVariant *serialised;

  serialised = dconf_changeset_serialise (change);

  return g_variant_new_from_data (G_VARIANT_TYPE ("(ay)"),
                                  g_variant_get_data (serialised), g_variant_get_size (serialised), TRUE,
                                  (GDestroyNotify) g_variant_unref, g_variant_ref_sink (serialised));
}

/* This function promotes changes from the pending queue to the
 * in-flight queue by sending the appropriate D-Bus message.
 *
 * Of course, this is only possible when there are pending items and
 * room in the in-flight queue.  For this reason, this function gets
 * called in two situations:
 *
 *   - an item has been added to the pending queue (due to an API call)
 *
 *   - an item has been removed from the inflight queue (due to a D-Bus
 *     reply having been received)
 *
 * It will move a maximum of one item.
 */
static void dconf_engine_manage_queue (DConfEngine *engine);

static void
dconf_engine_emit_changes (DConfEngine    *engine,
                           DConfChangeset *changeset,
                           gpointer        origin_tag)
{
  const gchar *prefix;
  const gchar * const *changes;

  if (dconf_changeset_describe (changeset, &prefix, &changes, NULL))
    dconf_engine_change_notify (engine, prefix, changes, NULL, origin_tag, engine->user_data);
}

static void
dconf_engine_change_completed (DConfEngine  *engine,
                               gpointer      handle,
                               GVariant     *reply,
                               const GError *error)
{
  OutstandingChange *oc = handle;

  dconf_engine_lock_queues (engine);

  /* D-Bus guarantees ordered delivery of messages.
   *
   * The dconf-service handles requests in-order.
   *
   * The reply we just received should therefore be at the head of
   * our 'in flight' queue.
   *
   * Due to https://bugs.freedesktop.org/show_bug.cgi?id=59780 it is
   * possible that we receive an out-of-sequence error message, however,
   * so only assume that messages are in-order for positive replies.
   */
  if (reply)
    {
      DConfChangeset *expected;

      expected = g_queue_pop_head (&engine->in_flight);
      g_assert (expected && oc->change == expected);
    }
  else
    {
      gboolean found;

      g_assert (error != NULL);

      found = g_queue_remove (&engine->in_flight, oc->change);
      g_assert (found);
    }

  /* We just popped a change from the in-flight queue, possibly
   * making room for another to be added.  Check that.
   */
  dconf_engine_manage_queue (engine);
  dconf_engine_unlock_queues (engine);

  /* Deal with the reply we got. */
  if (reply)
    {
      /* The write worked.
       *
       * We already sent a change notification for this item when we
       * added it to the pending queue and we don't want to send another
       * one again.  At the same time, it's very likely that we're just
       * about to receive a change signal from the service.
       *
       * The tag sent as part of the reply to the Change call will be
       * the same tag as on the change notification signal.  Record that
       * tag so that we can ignore the signal when it comes.
       *
       * last_handled is only ever touched from the worker thread
       */
      g_free (engine->last_handled);
      g_variant_get (reply, "(s)", &engine->last_handled);
    }

  if (error)
    {
      /* Some kind of unexpected failure occurred while attempting to
       * commit the change.
       *
       * There's not much we can do here except to drop our local copy
       * of the change (and notify that it is gone) and print the error
       * message as a warning.
       */
      g_warning ("failed to commit changes to dconf: %s", error->message);
      dconf_engine_emit_changes (engine, oc->change, NULL);
    }

  dconf_changeset_unref (oc->change);
  dconf_engine_call_handle_free (handle);
}

static void
dconf_engine_manage_queue (DConfEngine *engine)
{
  if (!g_queue_is_empty (&engine->pending) && g_queue_get_length (&engine->in_flight) < MAX_IN_FLIGHT)
    {
      OutstandingChange *oc;
      GVariant *parameters;

      oc = dconf_engine_call_handle_new (engine, dconf_engine_change_completed,
                                         G_VARIANT_TYPE ("(s)"), sizeof (OutstandingChange));

      oc->change = g_queue_pop_head (&engine->pending);

      parameters = dconf_engine_prepare_change (engine, oc->change);

      dconf_engine_dbus_call_async_func (engine->sources[0]->bus_type,
                                         engine->sources[0]->bus_name,
                                         engine->sources[0]->object_path,
                                         "ca.desrt.dconf.Writer", "Change",
                                         parameters, &oc->handle, NULL);

      g_queue_push_tail (&engine->in_flight, oc->change);
    }

  if (g_queue_is_empty (&engine->in_flight))
    {
      /* The in-flight queue should not be empty if we have changes
       * pending...
       */
      g_assert (g_queue_is_empty (&engine->pending));

      g_cond_broadcast (&engine->queue_cond);
    }
}

static gboolean
dconf_engine_is_writable_changeset_predicate (const gchar *key,
                                              GVariant    *value,
                                              gpointer     user_data)
{
  DConfEngine *engine = user_data;

  /* Resets absolutely always succeed -- even in the case that there is
   * not even a writable database.
   */
  return value == NULL || dconf_engine_is_writable_internal (engine, key);
}

static gboolean
dconf_engine_changeset_changes_only_writable_keys (DConfEngine    *engine,
                                                   DConfChangeset *changeset,
                                                   GError         **error)
{
  gboolean success = TRUE;

  dconf_engine_acquire_sources (engine);

  if (!dconf_changeset_all (changeset, dconf_engine_is_writable_changeset_predicate, engine))
    {
      g_set_error_literal (error, DCONF_ERROR, DCONF_ERROR_NOT_WRITABLE,
                           "The operation attempted to modify one or more non-writable keys");
      success = FALSE;
    }

  dconf_engine_release_sources (engine);

  return success;
}

gboolean
dconf_engine_change_fast (DConfEngine     *engine,
                          DConfChangeset  *changeset,
                          gpointer         origin_tag,
                          GError         **error)
{
  GList *node;

  if (dconf_changeset_is_empty (changeset))
    return TRUE;

  if (!dconf_engine_changeset_changes_only_writable_keys (engine, changeset, error))
    return FALSE;

  /* Check for duplicates in the pending queue.
   *
   * Note: order doesn't really matter here since "similarity" is an
   * equivalence class and we've ensured that there are no pairwise
   * similar changes in the queue already (ie: at most we will have only
   * one similar item to the one we are adding).
   */
  dconf_engine_lock_queues (engine);

  for (node = g_queue_peek_head_link (&engine->pending); node; node = node->next)
    {
      DConfChangeset *queued_change = node->data;

      if (dconf_changeset_is_similar_to (changeset, queued_change))
        {
          /* We found a similar item in the queue.
           *
           * We want to drop the one that's in the queue already since
           * we want our new (more recent) change to take precedence.
           *
           * The pending queue owned the changeset, so free it.
           */
          g_queue_delete_link (&engine->pending, node);
          dconf_changeset_unref (queued_change);

          /* There will only have been one, so stop looking. */
          break;
        }
    }

  /* No matter what we're going to queue up this change, so put it in
   * the pending queue now.
   *
   * There may be room in the in_flight queue, so we try to manage the
   * queue right away in order to try to promote it there (which causes
   * the D-Bus message to actually be sent).
   *
   * The change might get tossed before being sent if the loop above
   * finds it on a future call.
   */
  g_queue_push_tail (&engine->pending, dconf_changeset_ref (changeset));
  dconf_engine_manage_queue (engine);

  dconf_engine_unlock_queues (engine);

  /* Emit the signal after dropping the lock to avoid deadlock on re-entry. */
  dconf_engine_emit_changes (engine, changeset, origin_tag);

  return TRUE;
}

gboolean
dconf_engine_change_sync (DConfEngine     *engine,
                          DConfChangeset  *changeset,
                          gchar          **tag,
                          GError         **error)
{
  GVariant *reply;

  if (dconf_changeset_is_empty (changeset))
    {
      if (tag)
        *tag = g_strdup ("");

      return TRUE;
    }

  if (!dconf_engine_changeset_changes_only_writable_keys (engine, changeset, error))
    return FALSE;

  /* we know that we have at least one source because we checked writability */
  reply = dconf_engine_dbus_call_sync_func (engine->sources[0]->bus_type,
                                            engine->sources[0]->bus_name,
                                            engine->sources[0]->object_path,
                                            "ca.desrt.dconf.Writer", "Change",
                                            dconf_engine_prepare_change (engine, changeset),
                                            G_VARIANT_TYPE ("(s)"), error);

  if (reply == NULL)
    return FALSE;

  /* g_variant_get() is okay with NULL tag */
  g_variant_get (reply, "(s)", tag);
  g_variant_unref (reply);

  return TRUE;
}

void
dconf_engine_handle_dbus_signal (GBusType     type,
                                 const gchar *sender,
                                 const gchar *path,
                                 const gchar *member,
                                 GVariant    *body)
{
  if (g_str_equal (member, "Notify"))
    {
      const gchar *prefix;
      const gchar **changes;
      const gchar *tag;
      GSList *engines;

      if (!g_variant_is_of_type (body, G_VARIANT_TYPE ("(sass)")))
        return;

      g_variant_get (body, "(&s^a&s&s)", &prefix, &changes, &tag);

      g_mutex_lock (&dconf_engine_global_lock);
      engines = g_slist_copy_deep (dconf_engine_global_list, (GCopyFunc) dconf_engine_ref, NULL);
      g_mutex_unlock (&dconf_engine_global_lock);

      while (engines)
        {
          DConfEngine *engine = engines->data;

          /* It's possible that this incoming change notify is for a
           * change that we already announced to the client when we
           * placed it in the pending queue.
           *
           * Check last_handled to determine if we should ignore it.
           */
          if (!engine->last_handled || !g_str_equal (engine->last_handled, tag))
            dconf_engine_change_notify (engine, prefix, changes, tag, NULL, engine->user_data);

          engines = g_slist_delete_link (engines, engines);

          dconf_engine_unref (engine);
        }

      g_free (changes);
    }

  else if (g_str_equal (member, "WritabilityNotify"))
    {
      if (!g_variant_is_of_type (body, G_VARIANT_TYPE ("(s)")))
        return;

      g_warning ("Need to handle writability changes"); /* XXX */
    }
}

gboolean
dconf_engine_has_outstanding (DConfEngine *engine)
{
  gboolean has;

  /* The in-flight queue will never be empty unless the pending queue is
   * also empty, so we only really need to check one of them...
   */
  dconf_engine_lock_queues (engine);
  has = !g_queue_is_empty (&engine->in_flight);
  dconf_engine_unlock_queues (engine);

  return has;
}

void
dconf_engine_sync (DConfEngine *engine)
{
  dconf_engine_lock_queues (engine);
  while (!g_queue_is_empty (&engine->in_flight))
    g_cond_wait (&engine->queue_cond, &engine->queue_lock);
  dconf_engine_unlock_queues (engine);
}
