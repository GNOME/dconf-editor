#ifndef _dconf_client_h_
#define _dconf_client_h_

#include <dconf-resetlist.h>
#include <dconf-readtype.h>
#include <gio/gio.h>

G_BEGIN_DECLS

#define DCONF_TYPE_CLIENT       (dconf_client_get_type ())
#define DCONF_CLIENT(inst)      (G_TYPE_CHECK_INSTANCE_CAST ((inst), DCONF_TYPE_CLIENT, DConfClient))
#define DCONF_IS_CLIENT(inst)   (G_TYPE_CHECK_INSTANCE_TYPE ((inst), DCONF_TYPE_CLIENT))

typedef struct _DConfClient DConfClient;

typedef void          (*DConfWatchFunc)                                 (DConfClient          *client,
                                                                         const gchar          *path,
                                                                         const gchar * const  *items,
                                                                         gpointer              user_data);

GType                   dconf_client_get_type                           (void);
DConfClient *           dconf_client_new                                (const gchar          *context,
                                                                         DConfWatchFunc        watch_func,
                                                                         gpointer              user_data,
                                                                         GDestroyNotify        notify);

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
                                                                         guint64              *sequence,
                                                                         GCancellable         *cancellable,
                                                                         GError              **error);
void                    dconf_client_write_async                        (DConfClient          *client,
                                                                         const gchar          *key,
                                                                         GVariant             *value,
                                                                         GCancellable         *cancellable,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_write_finish                       (DConfClient          *client,
                                                                         GAsyncResult         *result,
                                                                         guint64              *sequence,
                                                                         GError              **error);

gboolean                dconf_client_set_locked                         (DConfClient          *client,
                                                                         const gchar          *path,
                                                                         gboolean              locked,
                                                                         GCancellable         *cancellable,
                                                                         GError              **error);
void                    dconf_client_set_locked_async                   (DConfClient          *client,
                                                                         const gchar          *path,
                                                                         gboolean              locked,
                                                                         GCancellable         *cancellable,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_set_locked_finish                  (DConfClient          *client,
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
G_END_DECLS

#endif
