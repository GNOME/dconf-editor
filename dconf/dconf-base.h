/*
 * Copyright © 2007 Ryan Lortie
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 */

#ifndef _dconf_base_h_
#define _dconf_base_h_

#include <glib.h>

#pragma GCC visibility push (default)

/* test a string for validity as a key or path */
gboolean    dconf_is_key   (const char *key);
gboolean    dconf_is_path  (const char *path);
gboolean    dconf_match    (const char *path_or_key1,
                            const char *path_or_key2);

#pragma GCC visibility pop

#endif /* _dconf_base_h_ */
