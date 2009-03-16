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

struct block_header
{
  guint32 size;
  guint32 reserved;
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
    guint32 index;
    guint64 direct;
  } data;
};

struct superblock
{
  char signature[8];
  guint32 root_index;
  char invalid;
  char type;
  char pad, padd;
};

#endif /* _dconf_format_h_ */
