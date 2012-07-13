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

GQueue outstanding_call_handles;

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
  g_queue_push_tail (&outstanding_call_handles, handle);

  return TRUE;
}

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
  g_assert_not_reached ();
}
