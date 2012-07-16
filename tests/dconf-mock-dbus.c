/*
 * Copyright © 2012 Canonical Limited
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

#include "../engine/dconf-engine.h"
#include "dconf-mock.h"

GQueue dconf_mock_dbus_outstanding_call_handles;

gboolean
dconf_engine_dbus_call_async_func (GBusType                bus_type,
                                   const gchar            *bus_name,
                                   const gchar            *object_path,
                                   const gchar            *interface_name,
                                   const gchar            *method_name,
                                   GVariant               *parameters,
                                   DConfEngineCallHandle  *handle,
                                   GError                **error)
{
  g_variant_ref_sink (parameters);
  g_variant_unref (parameters);

  g_queue_push_tail (&dconf_mock_dbus_outstanding_call_handles, handle);

  return TRUE;
}

DConfMockDBusSyncCallHandler dconf_mock_dbus_sync_call_handler;

GVariant *
dconf_engine_dbus_call_sync_func (GBusType             bus_type,
                                  const gchar         *bus_name,
                                  const gchar         *object_path,
                                  const gchar         *interface_name,
                                  const gchar         *method_name,
                                  GVariant            *parameters,
                                  const GVariantType  *reply_type,
                                  GError             **error)
{
  GVariant *reply;

  g_assert (dconf_mock_dbus_sync_call_handler != NULL);

  g_variant_ref_sink (parameters);

  reply = (* dconf_mock_dbus_sync_call_handler) (bus_type, bus_name, object_path, interface_name,
                                                 method_name, parameters, reply_type, error);

  g_variant_unref (parameters);

  return g_variant_take_ref (reply);
}
