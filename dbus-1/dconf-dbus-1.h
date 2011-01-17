/**
 * Copyright © 2010 Canonical Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the licence, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 **/

#ifndef _dconf_dbus_1_h_
#define _dconf_dbus_1_h_

#include <dbus/dbus.h>
#include <glib.h>

G_BEGIN_DECLS

typedef struct _DConfDBusClient DConfDBusClient;

typedef void         (* DConfDBusNotify)                                (DConfDBusClient *dcdbc,
                                                                         const gchar     *key,
                                                                         gpointer         user_data);

DConfDBusClient *       dconf_dbus_client_new                           (const gchar     *profile,
                                                                         DBusConnection  *session,
                                                                         DBusConnection  *system);
void                    dconf_dbus_client_unref                         (DConfDBusClient *dcdbc);
DConfDBusClient *       dconf_dbus_client_ref                           (DConfDBusClient *dcdbc);

GVariant *              dconf_dbus_client_read                          (DConfDBusClient *dcdbc,
                                                                         const gchar     *key);
gboolean                dconf_dbus_client_write                         (DConfDBusClient *dcdbc,
                                                                         const gchar     *key,
                                                                         GVariant        *value);
void                    dconf_dbus_client_subscribe                     (DConfDBusClient *dcdbc,
                                                                         const gchar     *name,
                                                                         DConfDBusNotify  notify,
                                                                         gpointer         user_data);
void                    dconf_dbus_client_unsubscribe                   (DConfDBusClient *dcdbc,
                                                                         DConfDBusNotify  notify,
                                                                         gpointer         user_data);
gboolean                dconf_dbus_client_has_pending                   (DConfDBusClient *dcdbc);

G_END_DECLS

#endif /* _dconf_dbus_1_h_ */
