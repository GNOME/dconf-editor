/*
 * Copyright © 2009 Codethink Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#ifndef _dconf_dbus_h_
#define _dconf_dbus_h_

#include "dconf-private-types.h"

typedef struct OPAQUE_TYPE__DConfDBusAsyncResult            DConfDBusAsyncResult;

typedef void          (*DConfDBusAsyncReadyCallback)                    (DConfDBusAsyncResult         *result,
                                                                         gpointer                      user_data);
typedef void          (*DConfDBusNotify)                                (const gchar                  *path,
                                                                         const gchar * const          *items,
                                                                         gint                          items_length,
                                                                         const gchar                  *event_id,
                                                                         gpointer                      user_data);

DConfDBus *             dconf_dbus_new                                  (const gchar                  *path,
                                                                         GError                      **error);

gboolean                dconf_dbus_set                                  (DConfDBus                    *bus,
                                                                         const gchar                  *path,
                                                                         GVariant                     *value,
                                                                         gchar                       **event_id,
                                                                         GError                      **error);
void                    dconf_dbus_set_async                            (DConfDBus                    *bus,
                                                                         const gchar                  *path,
                                                                         GVariant                     *value,
                                                                         DConfDBusAsyncReadyCallback   callback,
                                                                         gpointer                      user_data);

gboolean                dconf_dbus_reset                                (DConfDBus                    *bus,
                                                                         const gchar                  *path,
                                                                         gchar                       **event_id,
                                                                         GError                      **error);
void                    dconf_dbus_reset_async                          (DConfDBus                    *bus,
                                                                         const gchar                  *path,
                                                                         DConfDBusAsyncReadyCallback   callback,
                                                                         gpointer                      user_data);

gboolean                dconf_dbus_set_locked                           (DConfDBus                    *bus,
                                                                         const gchar                  *path,
                                                                         gboolean                      locked,
                                                                         GError                      **error);
void                    dconf_dbus_set_locked_async                     (DConfDBus                    *bus,
                                                                         const gchar                  *path,
                                                                         gboolean                      locked,
                                                                         DConfDBusAsyncReadyCallback   callback,
                                                                         gpointer                      user_data);

gboolean                dconf_dbus_merge                                (DConfDBus                    *bus,
                                                                         const gchar                  *prefix,
                                                                         GTree                        *values,
                                                                         gchar                       **event_id,
                                                                         GError                      **error);
void                    dconf_dbus_merge_async                          (DConfDBus                    *bus,
                                                                         const gchar                  *prefix,
                                                                         GTree                        *values,
                                                                         DConfDBusAsyncReadyCallback   callback,
                                                                         gpointer                      user_data);

gboolean                dconf_dbus_async_finish                         (DConfDBusAsyncResult         *result,
                                                                         const gchar                  *signature,
                                                                         gchar                       **event_id,
                                                                         GError                      **error);

void                    dconf_dbus_watch                                (DConfDBus                    *bus,
                                                                         const gchar                  *prefix,
                                                                         DConfDBusNotify               callback,
                                                                         gpointer                      user_data);
void                    dconf_dbus_unwatch                              (DConfDBus                    *bus,
                                                                         const gchar                  *prefix,
                                                                         DConfDBusNotify               callback,
                                                                         gpointer                      user_data);
void                    dconf_dbus_dispatch_error                       (DConfDBusAsyncReadyCallback   callback,
                                                                         gpointer                      user_data,
                                                                         GError                       *error);

#endif /* _dconf_dbus_h_ */
