/*
 * Copyright © 2007 Ryan Lortie
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 */

#include <string.h>

#include "dconf.h"

/**
 * dconf_is_key:
 * @key: a possible key
 *
 * Determines if @key is a valid key for use with
 * the dconf_gettable(), dconf_get(),
 * dconf_settable(), dconf_set() and dconf_unset()
 * functions.
 *
 * A key is valid if it starts with a slash, does
 * not end with a slash, and contains no two
 * consecutive slashes.  A key is different from a
 * path in that it does not end with "/".
 *
 * Returns %TRUE if @key is valid
 **/
gboolean
dconf_is_key (const char *key)
{
  int i;

  if (key == NULL)
    return FALSE;

  if (key[0] != '/')
    return FALSE;

  for (i = 0; key[i]; i++)
    if (key[i] == '/' && key[i + 1] == '/')
      return FALSE;

  return key[i - 1] != '/';
}

/**
 * dconf_is_path:
 * @path: a possible path
 *
 * Determines if @path is a valid key for use with
 * the dconf_list() function.
 *
 * A path is valid if it starts with a slash, ends
 * with a slash and contains no two consecutive
 * slashes.  A path is different from a key in
 * that it ends with "/".
 *
 * "/" is a valid path.
 *
 * Returns %TRUE if @path is valid
 **/
gboolean
dconf_is_path (const char *path)
{
  int i;

  if (path == NULL)
    return FALSE;

  if (path[0] != '/')
    return FALSE;

  for (i = 0; path[i]; i++)
    if (path[i] == '/' && path[i+1] == '/')
      return FALSE;

  return path[i - 1] == '/';
}

gboolean
dconf_match (const char *path_or_key1,
             const char *path_or_key2)
{
  int length1, length2;

  length1 = strlen (path_or_key1);
  length2 = strlen (path_or_key2);

  if (length1 < length2 && path_or_key1[length1 - 1] != '/')
    return FALSE;

  if (length2 < length1 && path_or_key2[length2 - 1] != '/')
    return FALSE;

  return memcmp (path_or_key1, path_or_key2, MIN (length1, length2)) == 0;
}
