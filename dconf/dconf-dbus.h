#ifndef _dconf_dbus_h_
#define _dconf_dbus_h_

#include "dconf-private-types.h"

typedef struct OPAQUE_TYPE__DConfDBusAsyncResult DConfDBusAsyncResult;
typedef void (*DConfDBusAsyncReadyCallback) (DConfDBusAsyncResult *, gpointer);
typedef void (*DConfDBusNotify) (const gchar *path, const gchar * const *items, guint32 sequence, gpointer user_data);

DConfDBus *             dconf_dbus_new                                  (const gchar                  *path,
                                                                         GError                      **error);

void                    dconf_dbus_watch                                (DConfDBus                    *bus,
                                                                         const gchar                  *prefix,
                                                                         DConfDBusNotify               callback,
                                                                         gpointer                      user_data);
void                    dconf_dbus_unwatch                              (DConfDBus                    *bus,
                                                                         const gchar                  *prefix,
                                                                         DConfDBusNotify               callback,
                                                                         gpointer                      user_data);

void                    dconf_dbus_merge_tree_async                     (DConfDBus                    *bus,
                                                                         const gchar                  *prefix,
                                                                         GTree                        *values,
                                                                         DConfDBusAsyncReadyCallback   callback,
                                                                         gpointer                      user_data);

gboolean                dconf_dbus_merge_finish                         (DConfDBusAsyncResult         *result,
                                                                         guint32                      *sequence,
                                                                         GError                      **error);

#endif /* _dconf_dbus_h_ */
