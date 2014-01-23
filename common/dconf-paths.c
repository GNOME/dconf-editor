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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "config.h"

#include "dconf-paths.h"

#include "dconf-error.h"

/**
 * SECTION:paths
 * @title: dconf Paths
 * @short_description: utility functions to validate dconf paths
 *
 * Various places in the dconf API speak of "paths", "keys", "dirs" and
 * relative versions of each of these.  This file contains functions to
 * check if a given string is a valid member of each of these classes
 * and to report errors when a string is not.
 *
 * See each function in this section for a precise description of what
 * makes a string a valid member of a given class.
 **/

#define vars gchar c, l

#define nonnull \
  if (string == NULL) {                                                 \
    g_set_error (error, DCONF_ERROR, DCONF_ERROR_PATH,                  \
                 "%s not specified", type);                             \
    return FALSE;                                                       \
  }


#define absolute \
  if ((l = *string++) != '/')                                           \
    {                                                                   \
      g_set_error (error, DCONF_ERROR, DCONF_ERROR_PATH,                \
                   "dconf %s must begin with a slash", type);           \
      return FALSE;                                                     \
    }

#define relative \
  if (*string == '/')                                                   \
    {                                                                   \
      g_set_error (error, DCONF_ERROR, DCONF_ERROR_PATH,                \
                   "dconf %s must not begin with a slash", type);       \
      return FALSE;                                                     \
    }                                                                   \
  l = '/'

#define no_double_slash \
  while ((c = *string++))                                               \
    {                                                                   \
      if (c == '/' && l == '/')                                         \
        {                                                               \
          g_set_error (error, DCONF_ERROR, DCONF_ERROR_PATH,            \
                       "dconf %s must not contain two "                 \
                       "consecutive slashes", type);                    \
          return FALSE;                                                 \
        }                                                               \
      l = c;                                                            \
    }                                                                   \

#define path \
  return TRUE

#define key \
  if (l == '/')                                                         \
    {                                                                   \
      g_set_error (error, DCONF_ERROR, DCONF_ERROR_PATH,                \
                   "dconf %s must not end with a slash", type);         \
      return FALSE;                                                     \
    }                                                                   \
  return TRUE

#define dir \
  if (l != '/')                                                         \
    {                                                                   \
      g_set_error (error, DCONF_ERROR, DCONF_ERROR_PATH,                \
                   "dconf %s must end with a slash", type);             \
      return FALSE;                                                     \
    }                                                                   \
  return TRUE



/**
 * dconf_is_path:
 * @string: a string
 * @error: a pointer to a #GError, or %NULL, set when %FALSE is returned
 *
 * Checks if @string is a valid dconf path.  dconf keys must start with
 * '/' and not contain '//'.
 *
 * A dconf path may be either a key or a dir.  See dconf_is_key() and
 * dconf_is_dir() for examples of each.
 *
 * Returns: %TRUE if @string is a path
 **/
gboolean
dconf_is_path (const gchar  *string,
               GError      **error)
{
#define type "path"
  vars; nonnull; absolute; no_double_slash; path;
#undef type
}

/**
 * dconf_is_key:
 * @string: a string
 * @error: a pointer to a #GError, or %NULL, set when %FALSE is returned
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
 *
 * Returns: %TRUE if @string is a key
 **/
gboolean
dconf_is_key (const gchar *string,
              GError      **error)
{
#define type "key"
  vars; nonnull; absolute; no_double_slash; key;
#undef type
}

/**
 * dconf_is_dir:
 * @string: a string
 * @error: a pointer to a #GError, or %NULL, set when %FALSE is returned
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
 *
 * Returns: %TRUE if @string is a dir
 **/
gboolean
dconf_is_dir (const gchar  *string,
              GError      **error)
{
#define type "dir"
  vars; nonnull; absolute; no_double_slash; dir;
#undef type
}

/**
 * dconf_is_rel_path:
 * @string: a string
 * @error: a pointer to a #GError, or %NULL, set when %FALSE is returned
 *
 * Checks if @string is a valid dconf relative path.  A relative path is
 * a string that, when concatenated to a dir, forms a valid dconf path.
 * This means that a rel must not start with a '/' or contain '//'.
 *
 * A dconf rel may be either a relative key or a relative dir.  See
 * dconf_is_rel_key() and dconf_is_rel_dir() for examples of each.
 *
 * Returns: %TRUE if @string is a relative path
 **/
gboolean
dconf_is_rel_path (const gchar  *string,
                   GError      **error)
{
#define type "relative path"
  vars; nonnull; relative; no_double_slash; path;
#undef type
}


/**
 * dconf_is_rel_key:
 * @string: a string
 * @error: a pointer to a #GError, or %NULL, set when %FALSE is returned
 *
 * Checks if @string is a valid dconf relative key.  A relative key is a
 * string that, when concatenated to a dir, forms a valid dconf key.
 * This means that a relative key must not start or end with a '/' or
 * contain '//'.
 *
 * "a", "a/b" and "a/b/c" are examples of relative keys.  "", "/", "/a",
 * "/a/b", "//a/b", "/a//b", and "a/" are examples of strings that are
 * not relative keys.
 *
 * Returns: %TRUE if @string is a relative key
 **/
gboolean
dconf_is_rel_key (const gchar  *string,
                  GError      **error)
{
#define type "relative key"
  vars; nonnull; relative; no_double_slash; key;
#undef type
}

/**
 * dconf_is_rel_dir:
 * @string: a string
 * @error: a pointer to a #GError, or %NULL, set when %FALSE is returned
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
 *
 * Returns: %TRUE if @string is a relative dir
 **/
gboolean
dconf_is_rel_dir (const gchar  *string,
                  GError      **error)
{
#define type "relative dir"
  vars; nonnull; relative; no_double_slash; dir;
#undef type
}
