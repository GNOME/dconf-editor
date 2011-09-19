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

#ifndef __dconf_client_h__
#define __dconf_client_h__

#include <gio/gio.h>

G_BEGIN_DECLS

#define DCONF_TYPE_CLIENT       (dconf_client_get_type ())
#define DCONF_CLIENT(inst)      (G_TYPE_CHECK_INSTANCE_CAST ((inst), DCONF_TYPE_CLIENT, DConfClient))
#define DCONF_IS_CLIENT(inst)   (G_TYPE_CHECK_INSTANCE_TYPE ((inst), DCONF_TYPE_CLIENT))

typedef GObjectClass DConfClientClass;
typedef struct _DConfClient DConfClient;

typedef void          (*DConfWatchFunc)                                 (DConfClient          *client,
                                                                         const gchar          *path,
                                                                         const gchar * const  *items,
                                                                         gint                  n_items,
                                                                         const gchar          *tag,
                                                                         gpointer              user_data);

GType                   dconf_client_get_type                           (void);

DConfClient *           dconf_client_new                                (const gchar          *profile,
                                                                         DConfWatchFunc        watch_func,
                                                                         gpointer              user_data,
                                                                         GDestroyNotify        notify);

GVariant *              dconf_client_read                               (DConfClient          *client,
                                                                         const gchar          *key);
GVariant *              dconf_client_read_default                       (DConfClient          *client,
                                                                         const gchar          *key);
GVariant *              dconf_client_read_no_default                    (DConfClient          *client,
                                                                         const gchar          *key);

gchar **                dconf_client_list                               (DConfClient          *client,
                                                                         const gchar          *dir,
                                                                         gint                 *length);

gboolean                dconf_client_is_writable                        (DConfClient          *client,
                                                                         const gchar          *key);

gboolean                dconf_client_write                              (DConfClient          *client,
                                                                         const gchar          *key,
                                                                         GVariant             *value,
                                                                         gchar               **tag,
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
                                                                         gchar               **tag,
                                                                         GError              **error);

gboolean                dconf_client_write_many                         (DConfClient          *client,
                                                                         const gchar          *dir,
                                                                         const gchar * const  *rels,
                                                                         GVariant            **values,
                                                                         gint                  n_values,
                                                                         gchar               **tag,
                                                                         GCancellable         *cancellable,
                                                                         GError              **error);

/* write_many_async currently disabled due to missing Vala functionality
void                    dconf_client_write_many_async                   (DConfClient          *client,
                                                                         const gchar          *dir,
                                                                         const gchar * const  *rels,
                                                                         GVariant            **values,
                                                                         gint                  n_values,
                                                                         GCancellable         *cancellable,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_write_many_finish                  (DConfClient          *client,
                                                                         GAsyncResult         *result,
                                                                         gchar               **tag,
                                                                         GError              **error);*/

gboolean                dconf_client_watch                              (DConfClient          *client,
                                                                         const gchar          *path,
                                                                         GCancellable         *cancellable,
                                                                         GError              **error);
void                    dconf_client_watch_async                        (DConfClient          *client,
                                                                         const gchar          *path,
                                                                         GCancellable         *cancellable,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_watch_finish                       (DConfClient          *client,
                                                                         GAsyncResult         *result,
                                                                         GError              **error);
gboolean                dconf_client_unwatch                            (DConfClient          *client,
                                                                         const gchar          *path,
                                                                         GCancellable         *cancellable,
                                                                         GError              **error);
void                    dconf_client_unwatch_async                      (DConfClient          *client,
                                                                         const gchar          *path,
                                                                         GCancellable         *cancellable,
                                                                         GAsyncReadyCallback   callback,
                                                                         gpointer              user_data);
gboolean                dconf_client_unwatch_finish                     (DConfClient          *client,
                                                                         GAsyncResult         *result,
                                                                         GError              **error);
G_END_DECLS

#endif /* __dconf_client_h__ */
