/*
 * Copyright © 2007, 2008  Ryan Lortie
 * Copyright © 2009 Codethink Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 2.1
 * of the licence, or (at your option) any later version.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#ifndef _dconf_writer_config_h_
#define _dconf_writer_config_h_

#include <glib.h>

typedef enum
{
  DCONF_WRITER_SESSION_BUS,
  DCONF_WRITER_SYSTEM_BUS
} DConfWriterBusType;

gboolean                dconf_writer_config_read                        (const gchar         *name,
                                                                         DConfWriterBusType  *bus_type,
                                                                         gchar              **bus_name,
                                                                         gchar              **filename,
                                                                         GError             **error);

#endif /* _dconf_writer_config_h_ */
