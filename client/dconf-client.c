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

#include <dconf-engine.h>
#include "dconf-client.h"
#include <string.h>

struct _DConfClient
{
  GObject parent_instance;

  GDBusConnection *session_bus;
  GDBusConnection *system_bus;

  DConfEngine *engine;
  gboolean will_write;

  DConfWatchFunc watch_func;
  gpointer user_data;
  GDestroyNotify notify;
};

G_DEFINE_TYPE (DConfClient, dconf_client, G_TYPE_OBJECT)

static GBusType
dconf_client_bus_type (DConfEngineMessage *dcem)
{
  switch (dcem->bus_type)
    {
    case 'e':
      return G_BUS_TYPE_SESSION;

    case 'y':
      return G_BUS_TYPE_SYSTEM;

    default:
      g_assert_not_reached ();
    }
}

typedef struct
{
  GSimpleAsyncResult *simple;
  GCancellable *cancellable;
  DConfEngineMessage dcem;
  GError *error;
} DConfClientAsyncOp;

static DConfClientAsyncOp *
dconf_client_async_op_new (DConfClient         *client,
                           gpointer             source_tag,
                           GCancellable        *cancellable,
                           GAsyncReadyCallback  callback,
                           gpointer             user_data)
{
  DConfClientAsyncOp *op;

  op = g_slice_new (DConfClientAsyncOp);
  op->simple = g_simple_async_result_new (G_OBJECT (client), callback,
                                          user_data, source_tag);
  if (cancellable)
    op->cancellable = g_object_ref (cancellable);
  else
    op->cancellable = NULL;

  op->error = NULL;

  return op;
}

static void
dconf_client_async_op_complete (DConfClientAsyncOp *op,
                                gboolean            in_idle)
{
  if (op->error != NULL)
    {
      g_assert (!g_simple_async_result_get_op_res_gpointer (op->simple));
      g_simple_async_result_set_from_error (op->simple, op->error);
      g_error_free (op->error);
    }

  else
    g_assert (g_simple_async_result_get_op_res_gpointer (op->simple) ||
              op->dcem.body == NULL);

  if (op->cancellable)
    g_object_unref (op->cancellable);

  if (op->dcem.body)
    g_variant_unref (op->dcem.body);

  if (in_idle)
    g_simple_async_result_complete_in_idle (op->simple);
  else
    g_simple_async_result_complete (op->simple);

  g_object_unref (op->simple);

  g_slice_free (DConfClientAsyncOp, op);
}

static gboolean
dconf_client_interpret_reply (DConfEngineMessage  *dcem,
                              GDBusMessage        *reply,
                              gchar              **tag,
                              GError             **error)
{
  gboolean success;

  if (reply == NULL)
    /* error will already have been set */
    return FALSE;

  
  success = dconf_engine_interpret_reply (dcem,
                                          g_dbus_message_get_sender (reply),
                                          g_dbus_message_get_body (reply),
                                          tag, error);
  g_object_unref (reply);

  return success;
}


static void
dconf_client_async_op_call_done (GObject      *object,
                                 GAsyncResult *result,
                                 gpointer      user_data)
{
  DConfClientAsyncOp *op = user_data;
  GDBusMessage *reply;

  reply = g_dbus_connection_send_message_with_reply_finish (G_DBUS_CONNECTION (object),
                                                            result, &op->error);

  if (reply != NULL)
    {
      gchar *tag;

      if (dconf_client_interpret_reply (&op->dcem, reply, &tag, &op->error))
        g_simple_async_result_set_op_res_gpointer (op->simple, tag, g_free);

      g_object_unref (reply);
    }

  dconf_client_async_op_complete (op, FALSE);
}

static void
dconf_client_async_op_get_bus_done (GObject      *no_object,
                                    GAsyncResult *result,
                                    gpointer      user_data)
{
  DConfClientAsyncOp *op = user_data;
  GDBusConnection *connection;

  if ((connection = g_bus_get_finish (result, &op->error)) && op->dcem.body)
    g_dbus_connection_call (connection, op->dcem.destination,
                            op->dcem.object_path, op->dcem.interface,
                            op->dcem.method, op->dcem.body,
                            op->dcem.reply_type, 0, -1, op->cancellable,
                            dconf_client_async_op_call_done, op);

  else
    dconf_client_async_op_complete (op, FALSE);
}

static void
dconf_client_async_op_run (DConfClientAsyncOp *op)
{
  if (op->error)
    dconf_client_async_op_complete (op, TRUE);
  else
    g_bus_get (dconf_client_bus_type (&op->dcem), op->cancellable,
               dconf_client_async_op_get_bus_done, op);
}

static gboolean
dconf_client_async_op_finish (gpointer       client,
                              GAsyncResult  *result,
                              gpointer       source_tag,
                              gchar        **tag,
                              GError       **error)
{
  GSimpleAsyncResult *simple;

  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);
  g_return_val_if_fail (g_simple_async_result_is_valid (result, client,
                                                        source_tag), FALSE);
  simple = G_SIMPLE_ASYNC_RESULT (result);

  if (g_simple_async_result_propagate_error (simple, error))
    return FALSE;

  if (tag)
    *tag = g_strdup (g_simple_async_result_get_op_res_gpointer (simple));

  return TRUE;
}

static void
dconf_client_finalize (GObject *object)
{
  DConfClient *client = DCONF_CLIENT (object);

  if (client->notify)
    client->notify (client->user_data);

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
  GObjectClass *object_class = G_OBJECT_CLASS (class);

  object_class->finalize = dconf_client_finalize;
}

/**
 * dconf_client_new:
 * @context: the context string (must by %NULL for now)
 * @will_write: %TRUE if you intend to use the client to write
 * @watch_func: the function to call when changes occur
 * @user_data: the user_data to pass to @watch_func
 * @notify: the function to free @user_data when no longer needed
 * Returns: a new #DConfClient
 *
 * Creates a new #DConfClient for the given context.
 *
 * If @will_write is %FALSE then you will not be able to use the created
 * client to write.  The benefit of this is that when combined with
 * @watch_func being %NULL, no connection to D-Bus is required.
 **/
DConfClient *
dconf_client_new (const gchar          *context,
                  gboolean              will_write,
                  DConfWatchFunc        watch_func,
                  gpointer              user_data,
                  GDestroyNotify        notify)
{
  DConfClient *client = g_object_new (DCONF_TYPE_CLIENT, NULL);

  client->engine = dconf_engine_new (context);
  client->will_write = will_write;
  client->watch_func = watch_func;
  client->user_data = user_data;
  client->notify = notify;

  return client;
}

/**
 * dconf_client_read:
 * @client: a #DConfClient
 * @key: a valid dconf key
 * Returns: the value corresponding to @key, or %NULL if there is none
 *
 * Reads the value named by @key from dconf.  If no such value exists,
 * %NULL is returned.
 **/
GVariant *
dconf_client_read (DConfClient   *client,
                   const gchar   *key)
{
  return dconf_engine_read (client->engine, key, DCONF_READ_NORMAL);
}

/**
 * dconf_client_read_default:
 * @client: a #DConfClient
 * @key: a valid dconf key
 * Returns: the default value corresponding to @key, or %NULL if there
 *           is none
 *
 * Reads the value named by @key from any existing default/mandatory
 * databases but ignoring any value set by the user.  The result is as
 * if the named key had just been reset.
 **/
GVariant *
dconf_client_read_default (DConfClient *client,
                           const gchar *key)
{
  return dconf_engine_read (client->engine, key, DCONF_READ_RESET);
}

/**
 * dconf_client_read_no_default:
 * @client: a #DConfClient
 * @key: a valid dconf key
 * Returns: the user value corresponding to @key, or %NULL if there is
 *           none
 *
 * Reads the value named by @key as set by the user, ignoring any
 * default/mandatory databases.  Normal applications will never want to
 * do this, but it may be useful for administrative or configuration
 * tweaking utilities to have access to this information.
 *
 * Note that in the case of mandatory keys, the result of
 * dconf_client_read_no_default() with a fallback to
 * dconf_client_read_default() is not necessarily the same as the result
 * of a dconf_client_read().  This is because the user may have set a
 * value before the key became marked as mandatory, in which case this
 * call will see the user's (otherwise inaccessible) key.
 **/
GVariant *
dconf_client_read_no_default (DConfClient *client,
                              const gchar *key)
{
  return dconf_engine_read (client->engine, key, DCONF_READ_SET);
}

static GDBusMessage *
dconf_client_create_call (DConfEngineMessage *dcem)
{
  GDBusMessage *message;

  message = g_dbus_message_new_method_call (dcem->destination,
                                            dcem->object_path,
                                            dcem->interface,
                                            dcem->method);
  g_dbus_message_set_body (message, dcem->body);

  return message;
}

static gboolean
dconf_client_call_sync (DConfClient          *client,
                        DConfEngineMessage   *dcem,
                        gchar               **tag,
                        GCancellable         *cancellable,
                        GError              **error)
{
  GDBusConnection *connection;

  connection = g_bus_get_sync (dconf_client_bus_type (dcem),
                               cancellable, error);

  if (connection == NULL)
    return FALSE;

  if (dcem->body)
    {
      GDBusMessage *message, *reply;

      message = dconf_client_create_call (dcem);
      reply = g_dbus_connection_send_message_with_reply_sync (connection,
                                                              message,
                                                              -1, NULL,
                                                              cancellable,
                                                              error);
      g_object_unref (message);

      return dconf_client_interpret_reply (dcem, reply, tag, error);
    }

  return TRUE;
}

/**
 * dconf_client_write:
 * @client: a #DConfClient
 * @key: a dconf key
 * @value: (allow-none): a #GVariant, or %NULL
 * @tag: (out) (allow-none): the tag from this write
 * @cancellable: a #GCancellable, or %NULL
 * @error: a pointer to a #GError, or %NULL
 * Returns: %TRUE if the write is successful
 *
 * Write a value to the given @key, or reset @key to its default value.
 *
 * If @value is %NULL then @key is reset to its default value (which may
 * be completely unset), otherwise @value becomes the new value.
 *
 * If @tag is non-%NULL then it is set to the unique tag associated with
 * this write.  This is the same tag that appears in change
 * notifications.
 **/
gboolean
dconf_client_write (DConfClient   *client,
                    const gchar   *key,
                    GVariant      *value,
                    gchar        **tag,
                    GCancellable  *cancellable,
                    GError       **error)
{
  DConfEngineMessage dcem;

  if (!dconf_engine_write (client->engine, &dcem, key, value, error))
    return FALSE;

  return dconf_client_call_sync (client, &dcem, tag, cancellable, error);
}

/**
 * dconf_client_write_async:
 * @client: a #DConfClient
 * @key: a dconf key
 * @value: (allow-none): a #GVariant, or %NULL
 * @cancellable: a #GCancellable, or %NULL
 * @callback: the function to call when complete
 * @user_data: the user data for @callback
 *
 * Writes a value to the given @key, or reset @key to its default value.
 *
 * This is the asynchronous version of dconf_client_write().  You should
 * call dconf_client_write_finish() from @callback to collect the
 * result.
 **/
void
dconf_client_write_async (DConfClient          *client,
                          const gchar          *key,
                          GVariant             *value,
                          GCancellable         *cancellable,
                          GAsyncReadyCallback   callback,
                          gpointer              user_data)
{
  DConfClientAsyncOp *op;

  op = dconf_client_async_op_new (client, dconf_client_write_async,
                                  cancellable, callback, user_data);
  dconf_engine_write (client->engine, &op->dcem, key, value, &op->error);
  dconf_client_async_op_run (op);
}

/**
 * dconf_client_write_finish:
 * @client: a #DConfClient
 * @result: the #GAsyncResult passed to the #GAsyncReadyCallback
 * @tag: (out) (allow-none): the tag from this write
 * @error: a pointer to a #GError, or %NULL
 *
 * Collects the result from a prior call to dconf_client_write_async().
 **/
gboolean
dconf_client_write_finish (DConfClient   *client,
                           GAsyncResult  *result,
                           gchar        **tag,
                           GError       **error)
{
  return dconf_client_async_op_finish (client, result,
                                       dconf_client_write_async,
                                       tag, error);
}

/**
 * dconf_client_list:
 * @client: a #DConfClient
 * @dir: a dconf dir
 * @length: the number of items that were returned
 * Returns: (array length=length): the paths located directly below @dir
 *
 * Lists the keys and dirs located directly below @dir.
 *
 * You should free the return result with g_strfreev() when it is no
 * longer needed.
 **/
gchar **
dconf_client_list (DConfClient    *client,
                   const gchar    *dir,
                   gsize          *length)
{
  return dconf_engine_list (client->engine, dir, NULL, length);
}

/**
 * dconf_client_set_locked:
 * @client: a #DConfClient
 * @path: a dconf path
 * @locked: %TRUE to lock, %FALSE to unlock
 * @cancellable: a #GCancellable, or %NULL
 * @error: a pointer to a #GError, or %NULL
 * Returns: %TRUE if setting the lock was successful
 *
 * Marks a dconf path as being locked.
 *
 * Locks do not affect writes to this #DConfClient.  You can still write
 * to a key that is marked as being locked without problems.
 *
 * Locks are only effective when they are set on a database that is
 * being used as the source of default/mandatory values.  In that case,
 * the lock will prevent writes from occuring to the database that has
 * this database as its defaults.
 **/
gboolean
dconf_client_set_locked (DConfClient   *client,
                         const gchar   *path,
                         gboolean       locked,
                         GCancellable  *cancellable,
                         GError       **error)
{
  DConfEngineMessage dcem;

  dconf_engine_set_locked (client->engine, &dcem, path, locked);

  return dconf_client_call_sync (client, &dcem, NULL, cancellable, error);
}

gboolean
dconf_client_is_writable (DConfClient  *client,
                          const gchar  *path,
                          GError      **error)
{
  DConfEngineMessage dcem;

  if (!dconf_engine_is_writable (client->engine, &dcem, path, error))
    return FALSE;

  return dconf_client_call_sync (client, &dcem, NULL, NULL, error);
}

gboolean
dconf_client_write_many (DConfClient          *client,
                         const gchar          *prefix,
                         const gchar * const  *rels,
                         GVariant            **values,
                         gchar               **tag,
                         GCancellable         *cancellable,
                         GError              **error)
{
  DConfEngineMessage dcem;

  if (!dconf_engine_write_many (client->engine, &dcem, prefix, rels, values, error))
    return FALSE;

  return dconf_client_call_sync (client, &dcem, tag, cancellable, error);
}

void
dconf_client_write_many_async (DConfClient          *client,
                               const gchar          *prefix,
                               const gchar * const  *rels,
                               GVariant            **values,
                               GCancellable         *cancellable,
                               GAsyncReadyCallback   callback,
                               gpointer              user_data)
{
  DConfClientAsyncOp *op;

  op = dconf_client_async_op_new (client, dconf_client_write_async,
                                  cancellable, callback, user_data);
  dconf_engine_write_many (client->engine, &op->dcem, prefix,
                           rels, values, &op->error);
  dconf_client_async_op_run (op);
}

gboolean
dconf_client_write_many_finish (DConfClient   *client,
                                GAsyncResult  *result,
                                gchar        **tag,
                                GError       **error)
{
  return dconf_client_async_op_finish (client, result,
                                       dconf_client_write_many_async,
                                       tag, error);
}

#if 0
gboolean                dconf_client_watch                              (DConfClient          *client,
                                                                         const gchar          *name,
                                                                         GError              **error);
void                    dconf_client_watch_async                        (DConfClient          *client,
                                                                         const gchar          *name,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_watch_finish                       (DConfClient          *client,
                                                                         GAsyncResult         *result,
                                                                         gpointer              user_data);
gboolean                dconf_client_unwatch                            (DConfClient          *client,
                                                                         const gchar          *name,
                                                                         GError              **error);
void                    dconf_client_unwatch_async                      (DConfClient          *client,
                                                                         const gchar          *name,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_unwatch_finish                     (DConfClient          *client,
                                                                         GAsyncResult         *result,
                                                                         gpointer              user_data);

#endif
