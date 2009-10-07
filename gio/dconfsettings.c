/*
 * Copyright © 2007, 2008  Ryan Lortie
 * Copyright © 2009 Codethink Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 2.1
 * of the licence, or (at your option) any later version.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#include <gio/gio.h>

#include "dconfstorage.h"

void g_io_module_load   (GIOModule *module);
void g_io_module_unload (GIOModule *module);

void
g_io_module_load (GIOModule *module)
{
  g_type_module_use (G_TYPE_MODULE (module));
  g_io_extension_point_implement ("gsettings-backend",
                                  DCONF_TYPE_STORAGE,
                                  "dconf-settings", 10);
}

void
g_io_module_unload (GIOModule *module)
{
  g_assert_not_reached ();
}
