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

gboolean                dconf_client_write                              (DConfClient          *client,
                                                                         const gchar          *key,
                                                                         GVariant             *value,
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


