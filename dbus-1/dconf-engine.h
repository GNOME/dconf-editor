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

#ifndef __dconf_engine_h__
#define __dconf_engine_h__

#include <glib.h>

typedef struct _DConfEngine DConfEngine;

/**
 * DConfEngineMessage:
 *
 * This structure represents a number of DBus method call messages that #DConfEngine would like to send.
 *
 * #DConfEngine itself is unaware of a particular DBus or main loop implementation.  As such, all requests are
 * synchronous and non-blocking, but most of them produce a #DConfEngineMessage describing messages that must be
 * sent in order for the operation to be completed.
 *
 * @bus_name, @object_path, @interface_name, @method_name specify the respective header fields of the method
 * call.  These are always equal for all of the calls contained within a single #DConfEngineMessage.
 *
 * @reply_type is the expected reply type of the method call.  This is also the same for all calls contained
 * within a single #DConfEngineMessage.
 *
 * @n_messages is the number of messages to send.
 *
 * @bus_types and @parameters are both arrays, of length @n_messages.  Each element of @bus_type is the bus type
 * to send each method call on and each of @parameters is the body of that call.  The reason that there may be
 * several messages is that a single dconf "watch" operation may need to send multiple DBus "AddMatch" calls
 * (and usually to multiple busses).
 *
 * Each element in @bus_types is either 'y' for system bus or 'e' for session bus.
 *
 * A #DConfEngineMessage is always stack-allocated by the caller.  It must be cleared using
 * dconf_engine_message_destroy() when done.  It may be copied using dconf_engine_message_copy().
 */
typedef struct
{
  const gchar         *bus_name;
  const gchar         *object_path;
  const gchar         *interface_name;
  const gchar         *method_name;

  gint                 n_messages;
  GVariant           **parameters;
  const gchar         *bus_types;

  const GVariantType  *reply_type;
} DConfEngineMessage;

G_GNUC_INTERNAL
void                    dconf_engine_message_copy                       (DConfEngineMessage      *orig,
                                                                         DConfEngineMessage      *copy);
G_GNUC_INTERNAL
void                    dconf_engine_message_destroy                    (DConfEngineMessage      *message);

G_GNUC_INTERNAL
DConfEngine *           dconf_engine_new                                (const gchar             *profile);
G_GNUC_INTERNAL
DConfEngine *           dconf_engine_new_for_db                         (const gchar             *db_name);
G_GNUC_INTERNAL
guint64                 dconf_engine_get_state                          (DConfEngine             *engine);

G_GNUC_INTERNAL
void                    dconf_engine_free                               (DConfEngine             *engine);

G_GNUC_INTERNAL
GVariant *              dconf_engine_read                               (DConfEngine             *engine,
                                                                         const gchar             *key);
G_GNUC_INTERNAL
GVariant *              dconf_engine_read_default                       (DConfEngine             *engine,
                                                                         const gchar             *key);
G_GNUC_INTERNAL
GVariant *              dconf_engine_read_no_default                    (DConfEngine             *engine,
                                                                         const gchar             *key);
G_GNUC_INTERNAL
gchar **                dconf_engine_list                               (DConfEngine             *engine,
                                                                         const gchar             *path,
                                                                         gint                    *length);

G_GNUC_INTERNAL
void                    dconf_engine_get_service_info                   (DConfEngine             *engine,
                                                                         const gchar            **bus_type,
                                                                         const gchar            **destination,
                                                                         const gchar            **object_path);
G_GNUC_INTERNAL
gboolean                dconf_engine_is_writable                        (DConfEngine             *engine,
                                                                         const gchar             *name);
G_GNUC_INTERNAL
gboolean                dconf_engine_write                              (DConfEngine             *engine,
                                                                         const gchar             *key,
                                                                         GVariant                *value,
                                                                         DConfEngineMessage      *message,
                                                                         GError                 **error);
G_GNUC_INTERNAL
gboolean                dconf_engine_write_many                         (DConfEngine             *engine,
                                                                         const gchar             *prefix,
                                                                         const gchar * const     *keys,
                                                                         GVariant               **values,
                                                                         DConfEngineMessage      *message,
                                                                         GError                 **error);
G_GNUC_INTERNAL
void                    dconf_engine_watch                              (DConfEngine             *engine,
                                                                         const gchar             *name,
                                                                         DConfEngineMessage      *message);
G_GNUC_INTERNAL
void                    dconf_engine_unwatch                            (DConfEngine             *engine,
                                                                         const gchar             *name,
                                                                         DConfEngineMessage      *message);
G_GNUC_INTERNAL
gboolean                dconf_engine_decode_notify                      (DConfEngine             *engine,
                                                                         const gchar             *anti_expose,
                                                                         const gchar            **prefix,
                                                                         const gchar           ***keys,
                                                                         guint                    bus_type,
                                                                         const gchar             *sender,
                                                                         const gchar             *interface,
                                                                         const gchar             *member,
                                                                         GVariant                *body);
G_GNUC_INTERNAL
gboolean                dconf_engine_decode_writability_notify          (const gchar            **path,
                                                                         const gchar             *iface,
                                                                         const gchar             *method,
                                                                         GVariant                *body);
#endif /* __dconf_engine_h__ */
