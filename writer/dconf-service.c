/*
 * Copyright © 2009 Codethink Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#include "dconf-service.h"

#include <glib.h>

#include "dconf-writer.h"

struct OPAQUE_TYPE__DConfService
{
  const gchar *name;

  DConfWriter *writers;
  gint n_writers;
};

gboolean
dconf_service_set (DConfService  *service,
                   const gchar   *key,
                   GVariant      *value,
                   guint32       *sequence,
                   GError       **error)
{
  *sequence = 7777;
  g_print ("set on %s\n", key);
//  g_set_error (error, 0, 0, "not supported yet");
  return TRUE;
}

gboolean
dconf_service_set_locked (DConfService  *service,
                          const gchar   *key,
                          gboolean       locked,
                          GError       **error)
{
  g_print ("set lock %s -> %d\n", key, locked);
  return TRUE;
}

DConfService *
dconf_service_new (const gchar  *name,
                   GError      **error)
{
  DConfService *service;

  service = g_slice_new (DConfService);
  service->name = g_strdup (name);

  return service;
}

const gchar *
dconf_service_get_bus_name (DConfService *service)
{
  return service->name;
}

DConfServiceBusType
dconf_service_get_bus_type (DConfService *service)
{
  return DCONF_SERVICE_SESSION_BUS;
}
