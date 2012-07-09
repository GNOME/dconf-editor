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

#include "../common/dconf-changeset.h"
#include "dconf-state.h"

typedef struct OPAQUE_TYPE__DConfWriter DConfWriter;

gchar **                dconf_writer_list_existing                      (void);
DConfWriter *           dconf_writer_new                                (DConfState           *state,
                                                                         const gchar          *name);
DConfState *            dconf_writer_get_state                          (DConfWriter          *writer);
const gchar *           dconf_writer_get_name                           (DConfWriter          *writer);
gboolean                dconf_writer_write                              (DConfWriter          *writer,
                                                                         const gchar          *name,
                                                                         GVariant             *value,
                                                                         GError              **error);
gboolean                dconf_writer_write_many                         (DConfWriter          *writer,
                                                                         const gchar          *prefix,
                                                                         const gchar * const  *keys,
                                                                         GVariant * const     *values,
                                                                         gsize n_items,
                                                                         GError              **error);

gboolean                dconf_writer_change                             (DConfWriter          *writer,
                                                                         DConfChangeset       *change,
                                                                         GError              **error);

#endif /* __dconf_writer_h__ */
