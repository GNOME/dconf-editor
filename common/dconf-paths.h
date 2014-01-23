/*
 * Copyright © 2008-2009 Ryan Lortie
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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#ifndef __dconf_paths_h__
#define __dconf_paths_h__

#include <glib.h>

gboolean                dconf_is_path                                   (const gchar         *string,
                                                                         GError             **error);
gboolean                dconf_is_key                                    (const gchar         *string,
                                                                         GError             **error);
gboolean                dconf_is_dir                                    (const gchar         *string,
                                                                         GError             **error);

gboolean                dconf_is_rel_path                               (const gchar         *string,
                                                                         GError             **error);
gboolean                dconf_is_rel_key                                (const gchar         *string,
                                                                         GError             **error);
gboolean                dconf_is_rel_dir                                (const gchar         *string,
                                                                         GError             **error);

#endif /* __dconf_paths_h__ */
