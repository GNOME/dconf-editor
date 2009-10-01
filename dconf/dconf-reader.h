/*
 * Copyright © 2007, 2008 Ryan Lortie
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

#ifndef _dconf_reader_h_
#define _dconf_reader_h_

#include "dconf-private-types.h"

#include <glib.h>

DConfReader *           dconf_reader_new                                (const gchar         *filename);

void                    dconf_reader_get                                (DConfReader         *reader,
                                                                         const gchar         *key,
                                                                         GVariant           **value,
                                                                         gboolean            *locked);

void                    dconf_reader_list                               (DConfReader         *reader,
                                                                         const gchar         *path,
                                                                         GTree               *builder,
                                                                         gboolean            *locked);

gboolean                dconf_reader_get_locked                         (DConfReader         *reader,
                                                                         const gchar         *name);

gboolean                dconf_reader_get_writable                       (DConfReader         *reader,
                                                                         const gchar         *name);
gboolean                dconf_reader_get_several_writable               (DConfReader         *reader,
                                                                         const gchar         *prefix,
                                                                         const gchar * const *items);

#endif /* _dconf_reader_h_ */
