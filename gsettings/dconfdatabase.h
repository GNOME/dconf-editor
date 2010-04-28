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

#ifndef _dconfdatabase_h_
#define _dconfdatabase_h_

#include <glib.h>

typedef struct _DConfDatabase DConfDatabase;

G_GNUC_INTERNAL
DConfDatabase * dconf_database_get_for_backend  (gpointer       backend);

G_GNUC_INTERNAL
GVariant *      dconf_database_read             (DConfDatabase *database,
                                                 const gchar   *key);
G_GNUC_INTERNAL
gchar **        dconf_database_list             (DConfDatabase *database,
                                                 const gchar   *path,
                                                 gsize         *length);
G_GNUC_INTERNAL
void            dconf_database_write            (DConfDatabase *database,
                                                 const gchar   *path_or_key,
                                                 GVariant      *value,
                                                 gpointer       origin_tag);
G_GNUC_INTERNAL
void            dconf_database_write_tree       (DConfDatabase *database,
                                                 GTree         *tree,
                                                 gpointer       origin_tag);
G_GNUC_INTERNAL
void            dconf_database_subscribe        (DConfDatabase *database,
                                                 const gchar   *name);
G_GNUC_INTERNAL
void            dconf_database_unsubscribe      (DConfDatabase *database,
                                                 const gchar   *name);

#endif
