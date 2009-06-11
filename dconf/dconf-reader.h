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

#include <glib/gvariant.h>
#include <glib/gtree.h>

void    dconf_reader_list          (const gchar  *filename,
                                    DConfReader **reader,
                                    const gchar  *path,
                                    GTree        *builder,
                                    gboolean     *locked);

void    dconf_reader_get           (const gchar  *filename,
                                    DConfReader **reader,
                                    const gchar  *key,
                                    GVariant    **value,
                                    gboolean     *locked);

void    dconf_reader_unref         (DConfReader  *reader);

#endif /* _dconf_reader_h_ */
