/*
 * Copyright © 2008-2009 Ryan Lortie
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

#include "dconf-paths.h"

#define vars gchar c, l

#define absolute \
  if ((l = *string++) != '/')           \
    return FALSE                        \

#define relative \
  l = '/'

#define no_double_slash \
  while ((c = *string++))               \
    {                                   \
      if (c == '/' && l == '/')         \
        return FALSE;                   \
      l = c;                            \
    }                                   \

#define path \
  return TRUE

#define key \
  return l != '/'

#define dir \
  return l == '/'



/**
 * dconf_is_path:
 * @string: a string
 * Returns: %TRUE if @string is a path
 *
 * Checks if @string is a valid dconf path.  dconf keys must start with
 * '/' and not contain '//'.
 *
 * A dconf path may be either a key or a dir.  See dconf_is_key() and
 * dconf_is_dir() for examples of each.
 **/
gboolean
dconf_is_path (const gchar *string)
{
  vars; absolute; no_double_slash; path;
}

/**
 * dconf_is_key:
 * @string: a string
 * Returns: %TRUE if @string is a key
 *
 * Checks if @string is a valid dconf key.  dconf keys must start with
 * '/', not contain '//' and not end with '/'.
 *
 * A dconf key is the potential location of a single value within the
 * database.
 *
 * "/a", "/a/b" and "/a/b/c" are examples of keys.  "", "/", "a", "a/b",
 * "//a/b", "/a//b", and "/a/" are examples of strings that are not
 * keys.
 **/
gboolean
dconf_is_key (const gchar *string)
{
  vars; absolute; no_double_slash; key;
}

/**
 * dconf_is_dir:
 * @string: a string
 * Returns: %TRUE if @string is a dir
 *
 * Checks if @string is a valid dconf dir.  dconf dirs must start and
 * end with '/' and not contain '//'.
 *
 * A dconf dir refers to a subtree of the database that can contain
 * other dirs or keys.  If @string is a dir, then it will be a prefix of
 * any key or dir contained within it.
 *
 * "/", "/a/" and "/a/b/" are examples of dirs.  "", "a/", "a/b/",
 * "//a/b/", "/a//b/" and "/a" are examples of strings that are not
 * dirs.
 **/
gboolean
dconf_is_dir (const gchar *string)
{
  vars; absolute; no_double_slash; dir;
}

/**
 * dconf_is_rel:
 * @string: a string
 * Returns: %TRUE if @string is a relative path
 *
 * Checks if @string is a valid dconf relative path.  A relative path is
 * a string that, when concatenated to a dir, forms a valid dconf path.
 * This means that a rel must not start with a '/' or contain '//'.
 *
 * A dconf rel may be either a relative key or a relative dir.  See
 * dconf_is_rel_key() and dconf_is_rel_dir() for examples of each.
 **/
gboolean
dconf_is_rel (const gchar *string)
{
  vars; relative; no_double_slash; path;
}


/**
 * dconf_is_rel_key:
 * @string: a string
 * Returns: %TRUE if @string is a relative key
 *
 * Checks if @string is a valid dconf relative key.  A relative key is a
 * string that, when concatenated to a dir, forms a valid dconf key.
 * This means that a relative key must not start or end with a '/' or
 * contain '//'.
 *
 * "a", "a/b" and "a/b/c" are examples of relative keys.  "", "/", "/a",
 * "/a/b", "//a/b", "/a//b", and "a/" are examples of strings that are
 * not relative keys.
 **/
gboolean
dconf_is_rel_key (const gchar *string)
{
  vars; relative; no_double_slash; key;
}

/**
 * dconf_is_rel_dir:
 * @string: a string
 * Returns: %TRUE if @string is a relative dir
 *
 * Checks if @string is a valid dconf relative dir.  A relative dir is a
 * string that, when appended to a dir, forms a valid dconf dir.  This
 * means that a relative dir must not start with a '/' or contain '//'
 * and must end with a '/' except in the case that it is the empty
 * string (in which case the path specified by appending the rel to a
 * directory is the original directory).
 *
 * "", "a/" and "a/b/" are examples of relative dirs.  "/", "/a/",
 * "/a/b/", "//a/b/", "a//b/" and "a" are examples of strings that are
 * not relative dirs.
 **/
gboolean
dconf_is_rel_dir (const gchar *string)
{
  vars; relative; no_double_slash; dir;
}
