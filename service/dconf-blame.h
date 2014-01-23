/*
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

#ifndef __dconf_blame_h__
#define __dconf_blame_h__

typedef struct _DConfBlame DConfBlame;

#include <gio/gio.h>

#define DCONF_TYPE_BLAME                                    (dconf_blame_get_type ())
#define DCONF_BLAME(inst)                                   (G_TYPE_CHECK_INSTANCE_CAST ((inst),                     \
                                                             DCONF_TYPE_BLAME, DConfBlame))
#define DCONF_IS_BLAME(inst)                                (G_TYPE_CHECK_INSTANCE_TYPE ((inst),                     \
                                                             DCONF_TYPE_BLAME))
#define DCONF_BLAME_GET_CLASS(inst)                         (G_TYPE_INSTANCE_GET_CLASS ((inst),                      \
                                                             DCONF_TYPE_BLAME, DConfBlameClass))

GType                   dconf_blame_get_type                            (void);
DConfBlame             *dconf_blame_get                                 (void);
void                    dconf_blame_record                              (GDBusMethodInvocation *invocation);

#endif /* __dconf_blame_h__ */
