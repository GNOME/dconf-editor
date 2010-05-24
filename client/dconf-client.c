#include <dconf-engine.h>
#include "dconf-client.h"
#include <string.h>

typedef GObjectClass DConfClientClass;

struct _DConfClient
{
  GObject parent_instance;

  DConfEngine *engine;

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

static void
dconf_client_async_op_call_done (GObject      *object,
                                 GAsyncResult *result,
                                 gpointer      user_data)
{
  DConfClientAsyncOp *op = user_data;
  GVariant *reply;

  if ((reply = g_dbus_connection_call_finish (G_DBUS_CONNECTION (object),
                                              result, &op->error)))
    g_simple_async_result_set_op_res_gpointer (op->simple, reply,
                                               (GDestroyNotify) g_variant_unref);

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
                              guint64       *sequence,
                              GError       **error)
{
  GSimpleAsyncResult *simple;

  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);
  g_return_val_if_fail (g_simple_async_result_is_valid (result, client,
                                                        source_tag), FALSE);
  simple = G_SIMPLE_ASYNC_RESULT (result);

  if (g_simple_async_result_propagate_error (simple, error))
    return FALSE;

  if (sequence)
    g_variant_get (g_simple_async_result_get_op_res_gpointer (simple),
                   "(t)", sequence);

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
  class->finalize = dconf_client_finalize;
}

DConfClient *
dconf_client_new (const gchar          *context,
                  DConfWatchFunc        watch_func,
                  gpointer              user_data,
                  GDestroyNotify        notify)
{
  DConfClient *client = g_object_new (DCONF_TYPE_CLIENT, NULL);

  client->engine = dconf_engine_new (context);
  client->watch_func = watch_func;
  client->user_data = user_data;
  client->notify = notify;

  return client;
}

GVariant *
dconf_client_read (DConfClient   *client,
                   const gchar   *key,
                   DConfReadType  type)
{
  return dconf_engine_read (client->engine, key, type);
}

static gboolean
dconf_client_call_sync (DConfClient          *client,
                        DConfEngineMessage   *dcem,
                        guint64              *sequence,
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
      GVariant *reply;

      reply = g_dbus_connection_call_sync (connection, dcem->destination,
                                           dcem->object_path, dcem->interface,
                                           dcem->method, dcem->body,
                                           dcem->reply_type,
                                           G_DBUS_CALL_FLAGS_NONE, -1,
                                           cancellable, error);

      if (reply == NULL)
        return FALSE;

      if (sequence)
        g_variant_get (reply, "(t)", sequence);

      g_variant_unref (reply);
    }

  return TRUE;
}

gboolean
dconf_client_write (DConfClient   *client,
                    const gchar   *key,
                    GVariant      *value,
                    guint64       *sequence,
                    GCancellable  *cancellable,
                    GError       **error)
{
  DConfEngineMessage dcem;

  if (!dconf_engine_write (client->engine, &dcem, key, value, error))
    return FALSE;

  return dconf_client_call_sync (client, &dcem, sequence, cancellable, error);
}

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

gboolean
dconf_client_write_finish (DConfClient   *client,
                           GAsyncResult  *result,
                           guint64       *sequence,
                           GError       **error)
{
  return dconf_client_async_op_finish (client, result,
                                       dconf_client_write_async,
                                       sequence, error);
}


gchar **
dconf_client_list (DConfClient    *client,
                   const gchar    *prefix,
                   DConfResetList *resets)
{
  return dconf_engine_list (client->engine, prefix, resets);
}

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
                         guint64              *sequence,
                         GCancellable         *cancellable,
                         GError              **error)
{
  DConfEngineMessage dcem;

  if (!dconf_engine_write_many (client->engine, &dcem, prefix, rels, values, error))
    return FALSE;

  return dconf_client_call_sync (client, &dcem, sequence, cancellable, error);
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
                                guint64       *sequence,
                                GError       **error)
{
  return dconf_client_async_op_finish (client, result,
                                       dconf_client_write_many_async,
                                       sequence, error);
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

