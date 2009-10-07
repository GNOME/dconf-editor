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

#ifndef _dconf_private_types_h_
#define _dconf_private_types_h_

#include <glib.h>

typedef struct OPAQUE_TYPE__DConfReader DConfReader;
typedef struct OPAQUE_TYPE__DConfDBus   DConfDBus;

typedef struct
{
  gchar *filename;
  DConfReader *reader;

  gchar *bus_name;
  DConfDBus *bus;
} DConfDB;

typedef struct
{
  const gchar *prefix;

  DConfDB **dbs;
  gint n_dbs;
} DConfMount;

#endif /* _dconf_private_types_h_ */
