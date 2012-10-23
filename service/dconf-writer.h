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
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#ifndef __dconf_writer_h__
#define __dconf_writer_h__

#include <gio/gio.h>

#define DCONF_TYPE_WRITER                                   (dconf_writer_get_type ())
#define DCONF_WRITER(inst)                                  (G_TYPE_CHECK_INSTANCE_CAST ((inst),                     \
                                                             DCONF_TYPE_WRITER, DConfWriter))
#define DCONF_IS_WRITER(inst)                               (G_TYPE_CHECK_INSTANCE_TYPE ((inst),                     \
                                                             DCONF_TYPE_WRITER))
#define DCONF_WRITER_GET_CLASS(inst)                        (G_TYPE_INSTANCE_GET_CLASS ((inst),                      \
                                                             DCONF_TYPE_WRITER, DConfWriterClass))

GDBusInterfaceSkeleton *dconf_writer_new                                (const gchar *filename);

#endif /* __dconf_writer_h__ */
