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

#ifndef _dconf_writer_h_
#define _dconf_writer_h_

#include <glib.h>

typedef struct OPAQUE_TYPE__DConfWriter DConfWriter;

DConfWriter *           dconf_writer_new                                (const gchar  *filename,
                                                                         GError      **error);

gboolean                dconf_writer_set                                (DConfWriter  *writer,
                                                                         const gchar  *key,
                                                                         GVariant     *value,
                                                                         GError      **error);

gboolean                dconf_writer_unset                              (DConfWriter  *writer,
                                                                         const gchar  *key,
                                                                         GError      **error);

gboolean                dconf_writer_set_locked                         (DConfWriter  *writer,
                                                                         const gchar  *key,
                                                                         gboolean      locked,
                                                                         GError      **error);

gboolean                dconf_writer_merge                              (DConfWriter  *writer,
                                                                         const gchar  *prefix,
                                                                         const gchar **names,
                                                                         GVariant    **values,
                                                                         gint          n_items,
                                                                         GError      **error);

void                    dconf_writer_dump                               (DConfWriter  *writer);

#endif /* _dconf_writer_h_ */
