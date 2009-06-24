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
                                                                         guint32                   sequence,
                                                                         gpointer                  user_data);

gboolean                dconf_is_key                                    (const gchar              *key);
gboolean                dconf_is_path                                   (const gchar              *path);
gboolean                dconf_match                                     (const gchar              *path_or_key1,
                                                                         const gchar              *path_or_key2);

GVariant *              dconf_get                                       (const gchar              *key);
gchar **                dconf_list                                      (const gchar              *path,
                                                                         gint                     *length);
gboolean                dconf_get_writable                              (const gchar              *path);
gboolean                dconf_get_locked                                (const gchar              *path);

gboolean                dconf_set                                       (const gchar              *key,
                                                                         GVariant                 *value,
                                                                         guint32                  *sequence,
                                                                         GError                  **error);

gboolean                dconf_set_locked                                (const gchar              *key,
                                                                         gboolean                  locked,
                                                                         GError                  **error);

gboolean                dconf_reset                                     (const gchar              *key,
                                                                         guint32                  *sequence,
                                                                         GError                  **error);

void                    dconf_merge_tree_async                          (const gchar              *prefix,
                                                                         GTree                    *tree,
                                                                         DConfAsyncReadyCallback   callback,
                                                                         gpointer                  user_data);

gboolean                dconf_merge_finish                              (DConfAsyncResult         *result,
                                                                         guint32                  *sequence,
                                                                         GError                  **error);

void                    dconf_watch                                     (const gchar              *match,
                                                                         DConfWatchFunc            func,
                                                                         gpointer                  user_data);

void                    dconf_unwatch                                   (const gchar              *match,
                                                                         DConfWatchFunc            func,
                                                                         gpointer                  user_data);

#endif /* _dconf_h_ */
