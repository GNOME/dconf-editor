#include <dconf-engine.h>
#include "dconf-client.h"

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
}

GVariant *
dconf_client_read (DConfClient   *client,
                   const gchar   *key,
                   DConfReadType  type)
{
  return dconf_engine_read (client->engine, key, type);
}

static GDBusConnection *
dconf_client_get_connection (guint    bus_type,
                             GError **error)
{
}

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
                                           G_DBUS_CALL_FLAGS_NONE, -1,
                                           cancellable, error);

      if (reply == NULL)
        return FALSE;

      if (!g_variant_is_of_type (reply, dcem->reply_type))
        {
          g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS,
                       "incorrect return type for '%s' method call",
                       dcem->method);
          g_variant_unref (reply);
          return FALSE;
        }

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

#if 0

GVariant *              dconf_client_read                               (DConfClient          *client,
                                                                         const gchar          *key,
                                                                         DConfReadType         type);

gchar **                dconf_client_list                               (DConfClient          *client,
                                                                         const gchar          *prefix,
                                                                         DConfResetList       *resets);

gboolean                dconf_client_is_writable                        (DConfClient          *client,
                                                                         const gchar          *prefix,
                                                                         GError              **error);

void                    dconf_client_write_async                        (DConfClient          *client,
                                                                         const gchar          *key,
                                                                         GVariant             *value,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_write_finish                       (DConfClient          *client,
                                                                         GAsyncResult         *result,
                                                                         GError              **error);

gboolean                dconf_client_write_many                         (DConfClient          *client,
                                                                         const gchar          *prefix,
                                                                         const gchar * const  *keys,
                                                                         GVariant            **values,
                                                                         GError              **error);
void                    dconf_client_write_many_async                   (DConfClient          *client,
                                                                         const gchar          *prefix,
                                                                         const gchar * const  *keys,
                                                                         GVariant            **values,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_write_many_finish                  (DConfClient          *client,
                                                                         GAsyncResult         *result,
                                                                         GError              **error);

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


