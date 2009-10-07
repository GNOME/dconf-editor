/*
 * Copyright © 2007-2008 Ryan Lortie
 * Copyright © 2009 Codethink Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 */

#ifndef _dconf_h_
#define _dconf_h_

#include <glib.h>

typedef struct OPAQUE_TYPE__DConfAsyncResult                DConfAsyncResult;

typedef void          (*DConfAsyncReadyCallback)                        (DConfAsyncResult         *result,
                                                                         gpointer                  user_data);
typedef void          (*DConfWatchFunc)                                 (const gchar              *prefix,
                                                                         const gchar * const      *items,
                                                                         gint                      items_length,
                                                                         const gchar              *event_id,
                                                                         gpointer                  user_data);

gboolean                dconf_is_key                                    (const gchar              *key);
gboolean                dconf_is_path                                   (const gchar              *path);
gboolean                dconf_is_key_or_path                            (const gchar              *key_or_path);
gboolean                dconf_is_relative_key                           (const gchar              *relative_key);
gboolean                dconf_match                                     (const gchar              *key_or_path1,
                                                                         const gchar              *key_or_path2);

GVariant *              dconf_get                                       (const gchar              *key);
gchar **                dconf_list                                      (const gchar              *path,
                                                                         gint                     *length);
gboolean                dconf_get_writable                              (const gchar              *key_or_path);
gboolean                dconf_get_locked                                (const gchar              *key_or_path);



gboolean                dconf_set                                       (const gchar              *key,
                                                                         GVariant                 *value,
                                                                         gchar                   **event_id,
                                                                         GError                  **error);
void                    dconf_set_async                                 (const gchar              *key,
                                                                         GVariant                 *value,
                                                                         DConfAsyncReadyCallback   callback,
                                                                         gpointer                  user_data);
gboolean                dconf_set_finish                                (DConfAsyncResult         *result,
                                                                         gchar                   **event_id,
                                                                         GError                  **error);


gboolean                dconf_set_locked                                (const gchar              *key_or_path,
                                                                         gboolean                  locked,
                                                                         GError                  **error);
void                    dconf_set_locked_async                          (const gchar              *key_or_path,
                                                                         gboolean                  locked,
                                                                         DConfAsyncReadyCallback   callback,
                                                                         gpointer                  user_data);
gboolean                dconf_set_locked_finish                         (DConfAsyncResult         *result,
                                                                         GError                  **error);


gboolean                dconf_reset                                     (const gchar              *key,
                                                                         gchar                   **event_id,
                                                                         GError                  **error);
void                    dconf_reset_async                               (const gchar              *key,
                                                                         DConfAsyncReadyCallback   callback,
                                                                         gpointer                  user_data);
gboolean                dconf_reset_finish                              (DConfAsyncResult         *result,
                                                                         gchar                   **event_id,
                                                                         GError                  **error);


gboolean                dconf_merge                                     (const gchar              *prefix,
                                                                         GTree                    *tree,
                                                                         gchar                   **event_id,
                                                                         GError                  **error);
void                    dconf_merge_async                               (const gchar              *prefix,
                                                                         GTree                    *tree,
                                                                         DConfAsyncReadyCallback   callback,
                                                                         gpointer                  user_data);
gboolean                dconf_merge_finish                              (DConfAsyncResult         *result,
                                                                         gchar                   **event_id,
                                                                         GError                  **error);


void                    dconf_watch                                     (const gchar              *match,
                                                                         DConfWatchFunc            func,
                                                                         gpointer                  user_data);

void                    dconf_unwatch                                   (const gchar              *match,
                                                                         DConfWatchFunc            func,
                                                                         gpointer                  user_data);

#endif /* _dconf_h_ */
