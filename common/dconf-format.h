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

#ifndef _dconf_format_h_
#define _dconf_format_h_

#include <glib.h>

struct chunk_header
{
  guint32 size;
  guint32 reserved;

  gchar contents[0];
};

struct dir_entry
{
  guchar type;
  guchar namelen;
  guchar locked;
  guchar pad2;

  union
  {
    char direct[36];
    guint32 index;
  } name;

  union
  {
    guint8  byte;
    guint16 uint16;
    guint32 uint32;
    guint64 uint64;
    gdouble floating;

    guint32 index;
  } data;
};

#define DCONF_SIGNATURE_0    1852793700
#define DCONF_SIGNATURE_1     813047910

#define DCONF_FLAG_STALE    1
#define DCONF_FLAG_LOCKED   2

struct superblock
{
  guint32 signature[2];

  guint32 root_index;
  guint32 next;

  char flags;

  char type;
  char pad, padd;

  guint32 pade;
  guint32 padf, padg;
};

#endif /* _dconf_format_h_ */
