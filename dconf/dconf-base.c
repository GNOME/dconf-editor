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
 * @Returns: %TRUE if @key is valid
 *
 * Determines if @key is a valid key.
 *
 * A key is valid if it starts with a slash, does
 * not end with a slash, and contains no two
 * consecutive slashes.  A key is different from a
 * path in that it does not end with "/".
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
 * @Returns: %TRUE if @path is valid
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

/**
 * dconf_is_key_or_path:
 * @key_or_path: a possible key or path
 * @Returns: %TRUE if @key_or_path is valid
 *
 * Determines if @key_or_path is a valid key or path.
 **/
gboolean
dconf_is_key_or_path (const gchar *key_or_path)
{
  int i;

  if (key_or_path == NULL)
    return FALSE;

  if (key_or_path[0] != '/')
    return FALSE;

  for (i = 0; key_or_path[i]; i++)
    if (key_or_path[i] == '/' && key_or_path[i + 1] == '/')
      return FALSE;

  return TRUE;
}

/**
 * dconf_match:
 * @key_or_path1: a dconf key or path
 * @key_or_path2: a dconf key or path
 * @Returns: %TRUE iff @key_or_path1 matches @key_or_path2
 *
 * Checks if @key_or_path1 matches @key_or_path2.
 *
 * Match is a symmetric predicate on a pair of strings defined as
 * follows: two strings match if and only if they are exactly equal or
 * one of them ends with a slash and is a prefix of the other.
 *
 * The match predicate is of significance in two parts of the dconf API.
 *
 * First, when registering watches for change notifications, any key
 * that matches the requested watch will be reported.  This means that
 * if your watch string ends with a slash then changes to any key that
 * has the watch string as the initial part of its path will be
 * reported.
 *
 * Second, any lock set on the database will restrict write access to
 * any key that matches the lock.  This means that if your lock string
 * ends with a slash then no key that has the lock string as it prefix
 * may be written to.
 **/
gboolean
dconf_match (const char *key_or_path1,
             const char *key_or_path2)
{
  int length1, length2;

  length1 = strlen (key_or_path1);
  length2 = strlen (key_or_path2);

  if (length1 < length2 && key_or_path1[length1 - 1] != '/')
    return FALSE;

  if (length2 < length1 && key_or_path2[length2 - 1] != '/')
    return FALSE;

  return memcmp (key_or_path1, key_or_path2, MIN (length1, length2)) == 0;
}
