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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#ifndef __dconf_engine_h__
#define __dconf_engine_h__

#include "../common/dconf-changeset.h"

#include <gio/gio.h>

typedef struct _DConfEngine DConfEngine;

typedef struct _DConfEngineCallHandle DConfEngineCallHandle;

/* These functions need to be implemented by the client library */
G_GNUC_INTERNAL
void                    dconf_engine_dbus_init_for_testing              (void);

/* Sends a D-Bus message.
 *
 * When the reply comes back, the client library should call
 * dconf_engine_handle_dbus_reply with the given user_data.
 *
 * This is called with the engine lock held.  Re-entering the engine
 * from this function will cause a deadlock.
 */
G_GNUC_INTERNAL
gboolean                dconf_engine_dbus_call_async_func               (GBusType                 bus_type,
                                                                         const gchar             *bus_name,
                                                                         const gchar             *object_path,
                                                                         const gchar             *interface_name,
                                                                         const gchar             *method_name,
                                                                         GVariant                *parameters,
                                                                         DConfEngineCallHandle   *handle,
                                                                         GError                 **error);

/* Sends a D-Bus message, synchronously.
 *
 * The lock is never held when calling this function (for the sake of
 * not blocking requests in other threads) but you should have no reason
 * to re-enter, so don't.
 */
G_GNUC_INTERNAL
GVariant *              dconf_engine_dbus_call_sync_func                (GBusType                 bus_type,
                                                                         const gchar             *bus_name,
                                                                         const gchar             *object_path,
                                                                         const gchar             *interface_name,
                                                                         const gchar             *method_name,
                                                                         GVariant                *parameters,
                                                                         const GVariantType      *expected_type,
                                                                         GError                 **error);

/* Notifies that a change occured.
 *
 * The engine lock is never held when calling this function so it is
 * safe to run user callbacks or emit signals from this function.
 */
G_GNUC_INTERNAL
void                    dconf_engine_change_notify                      (DConfEngine             *engine,
                                                                         const gchar             *prefix,
                                                                         const gchar * const     *changes,
                                                                         const gchar             *tag,
                                                                         gboolean                 is_writability,
                                                                         gpointer                 origin_tag,
                                                                         gpointer                 user_data);

/* These functions are implemented by the engine */
G_GNUC_INTERNAL
const GVariantType *    dconf_engine_call_handle_get_expected_type      (DConfEngineCallHandle   *handle);
G_GNUC_INTERNAL
void                    dconf_engine_call_handle_reply                  (DConfEngineCallHandle   *handle,
                                                                         GVariant                *parameters,
                                                                         const GError            *error);

G_GNUC_INTERNAL
void                    dconf_engine_handle_dbus_signal                 (GBusType                 bus_type,
                                                                         const gchar             *bus_name,
                                                                         const gchar             *object_path,
                                                                         const gchar             *signal_name,
                                                                         GVariant                *parameters);

G_GNUC_INTERNAL
DConfEngine *           dconf_engine_new                                (const gchar             *profile,
                                                                         gpointer                 user_data,
                                                                         GDestroyNotify           free_func);

G_GNUC_INTERNAL
void                    dconf_engine_unref                              (DConfEngine             *engine);

/* Read API: always handled immediately */
G_GNUC_INTERNAL
guint64                 dconf_engine_get_state                          (DConfEngine             *engine);

G_GNUC_INTERNAL
gboolean                dconf_engine_is_writable                        (DConfEngine             *engine,
                                                                         const gchar             *key);

G_GNUC_INTERNAL
GVariant *              dconf_engine_read                               (DConfEngine             *engine,
                                                                         GQueue                  *read_through,
                                                                         const gchar             *key);

G_GNUC_INTERNAL
GVariant *              dconf_engine_read_user_value                    (DConfEngine             *engine,
                                                                         GQueue                  *read_through,
                                                                         const gchar             *key);

G_GNUC_INTERNAL
gchar **                dconf_engine_list                               (DConfEngine             *engine,
                                                                         const gchar             *dir,
                                                                         gint                    *length);

/* "Fast" API: all calls return immediately and look like they succeeded (from a local viewpoint) */
G_GNUC_INTERNAL
void                    dconf_engine_watch_fast                         (DConfEngine             *engine,
                                                                         const gchar             *path);

G_GNUC_INTERNAL
void                    dconf_engine_unwatch_fast                       (DConfEngine             *engine,
                                                                         const gchar             *path);

G_GNUC_INTERNAL
gboolean                dconf_engine_change_fast                        (DConfEngine             *engine,
                                                                         DConfChangeset          *changeset,
                                                                         gpointer                 origin_tag,
                                                                         GError                 **error);

/* Synchronous API: all calls block until completed */
G_GNUC_INTERNAL
void                    dconf_engine_watch_sync                         (DConfEngine             *engine,
                                                                         const gchar             *path);

G_GNUC_INTERNAL
void                    dconf_engine_unwatch_sync                       (DConfEngine             *engine,
                                                                         const gchar             *path);

G_GNUC_INTERNAL
gboolean                dconf_engine_change_sync                        (DConfEngine             *engine,
                                                                         DConfChangeset          *changeset,
                                                                         gchar                  **tag,
                                                                         GError                 **error);
G_GNUC_INTERNAL
gboolean                dconf_engine_has_outstanding                    (DConfEngine             *engine);
G_GNUC_INTERNAL
void                    dconf_engine_sync                               (DConfEngine             *engine);

/* Asynchronous API: not implemented yet (and maybe never?) */

#endif /* __dconf_engine_h__ */
