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

#include <gio/gsettingsstorage.h>
#include <gio/gio.h>

void g_io_module_load   (GIOModule *module);
void g_io_module_unload (GIOModule *module);
static GType dconf_settings_get_type (void);

typedef struct
{
  GSettingsStorage parent_instance;

} DConfSettings;

typedef GSettingsStorageClass DConfSettingsClass;

G_DEFINE_TYPE (DConfSettings, dconf_settings, G_TYPE_SETTINGS_STORAGE)

static void
dconf_settings_init (DConfSettings *settings)
{
}

static void
dconf_settings_class_init (DConfSettingsClass *class)
{
}

void
g_io_module_load (GIOModule *module)
{
  g_type_module_use (G_TYPE_MODULE (module));
  g_io_extension_point_implement ("gsettings-storage",
                                  dconf_settings_get_type (),
                                  "dconf-settings", 10);
}

void
g_io_module_unload (GIOModule *module)
{
  g_assert_not_reached ();
}
