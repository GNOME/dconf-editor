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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
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

void
dconf_mock_dbus_async_reply (GVariant *reply,
                             GError   *error)
{
  DConfEngineCallHandle *handle;

  g_assert (!g_queue_is_empty (&dconf_mock_dbus_outstanding_call_handles));
  handle = g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles);

  if (reply)
    {
      const GVariantType *expected_type;

      expected_type = dconf_engine_call_handle_get_expected_type (handle);
      g_assert (expected_type == NULL || g_variant_is_of_type (reply, expected_type));
      g_variant_ref_sink (reply);
    }

  dconf_engine_call_handle_reply (handle, reply, error);

  if (reply)
    g_variant_unref (reply);
}

void
dconf_mock_dbus_assert_no_async (void)
{
  g_assert (g_queue_is_empty (&dconf_mock_dbus_outstanding_call_handles));
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

  g_assert (reply != NULL || (error == NULL || *error != NULL));

  return reply ? g_variant_take_ref (reply) : NULL;
}
