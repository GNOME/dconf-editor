/*
 * Copyright © 2010 Codethink Limited
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

#ifndef __dconf_engine_source_private_h__
#define __dconf_engine_source_private_h__

#include "dconf-engine-source.h"

G_GNUC_INTERNAL extern const DConfEngineSourceVTable dconf_engine_source_file_vtable;
G_GNUC_INTERNAL extern const DConfEngineSourceVTable dconf_engine_source_user_vtable;
G_GNUC_INTERNAL extern const DConfEngineSourceVTable dconf_engine_source_service_vtable;
G_GNUC_INTERNAL extern const DConfEngineSourceVTable dconf_engine_source_system_vtable;

#endif /* __dconf_engine_source_private_h__ */
