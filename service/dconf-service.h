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

#ifndef __dconf_service_h__
#define __dconf_service_h__

#include <gio/gio.h>

#define DCONF_TYPE_SERVICE                                  (dconf_service_get_type ())
#define DCONF_SERVICE(inst)                                 (G_TYPE_CHECK_INSTANCE_CAST ((inst),                     \
                                                             DCONF_TYPE_SERVICE, DConfService))
#define DCONF_IS_SERVICE(inst)                              (G_TYPE_CHECK_INSTANCE_TYPE ((inst),                     \
                                                             DCONF_TYPE_SERVICE))

GType                   dconf_service_get_type                          (void);
GApplication *          dconf_service_new                               (void);

#endif /* __dconf_service_h__ */
