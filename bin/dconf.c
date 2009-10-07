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

#include <string.h>
#include <getopt.h>
#include <stdio.h>

#include <dconf.h>
#include <glib.h>

static const char usage_message[] =
"usage: dconf [--version] [--async] [--help] COMMAND [ARGS]\n";

static const char help_message[] =
"\n"
"The valid commands are:\n"
"   is-key              check if a string is a valid dconf key\n"
"   is-path             check if a string is a valid dconf path\n"
"   is-key-or-path      check if a string is a valid dconf key or path\n"
"   is-relative-key     check if a string is a valid dconf relative key\n"
"   match               check if two strings are a dconf match\n"
"   get                 get the value of a key from dconf\n"
"   list                list the entries at a path in dconf\n"
"   get-writable        check if a dconf key is writable\n"
"   get-locked          check if a dconf key is locked\n"
"   set                 set a key to a value\n"
"   reset               reset a key to its default value\n"
"   set-locked          lock or unlock a key or path\n"
"   merge               set several values at once\n"
"\n"
"See 'dconf help COMMAND' for more information on a specific command.\n";

struct option longopts[] = {
  { "version", no_argument, NULL, 'v' },
  { "async",   no_argument, NULL, 'a' },
  { "help",    no_argument, NULL, 'h' }
};

union result
{
  gboolean boolean;
  gchar *string;
};

struct asyncinfo
{
  gboolean success;
  GError *error;
  union result result;
  GMainLoop *loop;
};

static void
async_init (struct asyncinfo *asi)
{
  asi->error = NULL;
  asi->loop = g_main_loop_new (NULL, FALSE);
}

static gboolean
async_wait (struct asyncinfo  *asi,
            union result      *result,
            GError           **error)
{
  g_main_loop_run (asi->loop);

  if (asi->success)
    *result = asi->result;
  else
    g_propagate_error (error, asi->error);

  g_main_loop_unref (asi->loop);

  asi->result.string = NULL;
  asi->error = NULL;
  asi->loop = NULL;

  return asi->success;
}

static void
async_done (struct asyncinfo *asi)
{
  g_main_loop_quit (asi->loop);
}

#define throw(...) \
  G_STMT_START {                                \
    g_set_error (error, 0, 0, __VA_ARGS__);     \
    return 0;                                   \
  } G_STMT_END

static gboolean
is_key (gint           argc,
        gchar        **argv,
        gboolean       async,
        union result  *result,
        GError       **error)
{
  if (argc != 1)
    throw ("expected one string to check");

  result->boolean = dconf_is_key (argv[0]);
  return TRUE;
}

static gboolean
is_path (gint           argc,
         gchar        **argv,
         gboolean       async,
         union result  *result,
         GError       **error)
{
  if (argc != 1)
    throw ("expected one string to check");

  result->boolean = dconf_is_path (argv[0]);
  return TRUE;
}

static gboolean
is_key_or_path (gint           argc,
                gchar        **argv,
                gboolean       async,
                union result  *result,
                GError       **error)
{
  if (argc != 1)
    throw ("expected one string to check");

  result->boolean = dconf_is_key_or_path (argv[0]);
  return TRUE;
}

static gboolean
is_relative_key (gint           argc,
                 gchar        **argv,
                 gboolean       async,
                 union result  *result,
                 GError       **error)
{
  if (argc != 1)
    throw ("expected one string to check");

  result->boolean = dconf_is_relative_key (argv[0]);
  return TRUE;
}

static gboolean
match (gint           argc,
       gchar        **argv,
       gboolean       async,
       union result  *result,
       GError       **error)
{
  if (argc != 2)
    throw ("expected two strings to check");

  result->boolean = dconf_match (argv[0], argv[1]);
  return TRUE;
}

static gboolean
get (gint           argc,
     gchar        **argv,
     gboolean       async,
     union result  *result,
     GError       **error)
{
  GVariant *value;

  if (argc != 1 || !dconf_is_key (argv[0]))
    throw ("expected one key");

  value = dconf_get (argv[0]);

  if (value != NULL)
    {
      gchar *str;

      str = g_variant_print (value, TRUE);
      printf ("%s\n", str);
      g_free (str);

      g_variant_unref (value);
    }

  return value != NULL;
}

static gboolean
list (gint           argc,
      gchar        **argv,
      gboolean       async,
      union result  *result,
      GError       **error)
{
  gchar **list;
  gint i;

  if (argc != 1 || !dconf_is_path (argv[0]))
    throw ("expected one path");

  list = dconf_list (argv[0], NULL);

  for (i = 0; list[i]; i++)
    g_print ("%s\n", list[i]);

  g_strfreev (list);

  return i > 0;
}

static gboolean
get_writable (gint           argc,
              gchar        **argv,
              gboolean       async,
              union result  *result,
              GError       **error)
{
  if (argc != 1 || !dconf_is_key_or_path (argv[0]))
    throw ("expected key or path");

  result->boolean = dconf_get_writable (argv[0]);
  return TRUE;
}

static gboolean
get_locked (gint           argc,
            gchar        **argv,
            gboolean       async,
            union result  *result,
            GError       **error)
{
  if (argc != 1 || !dconf_is_key_or_path (argv[0]))
    throw ("expected key or path");

  result->boolean = dconf_get_locked (argv[0]);
  return TRUE;
}

static void
set_done (DConfAsyncResult *result,
          gpointer          user_data)
{
  struct asyncinfo *asi = user_data;

  asi->success = dconf_set_finish (result,
                                   &asi->result.string,
                                   &asi->error);
  async_done (asi);
}

static gboolean
set (gint           argc,
     gchar        **argv,
     gboolean       async,
     union result  *result,
     GError       **error)
{
  gboolean success = FALSE;
  GVariant *value;
  gchar *string;

  if (argc < 2 || !dconf_is_key (argv[0]))
    throw ("expected key and value");

  string = g_strjoinv (" ", argv + 1);
  value = g_variant_parse (string, -1, NULL, error);
  g_free (string);

  if (value != NULL)
    {
      if (async)
        {
          struct asyncinfo asi;

          async_init (&asi);
          dconf_set_async (argv[0], value, set_done, &asi);
          success = async_wait (&asi, result, error);
        }
      else
        success = dconf_set (argv[0], value, &result->string, error);

      g_variant_unref (value);
    }

  return success;
}

static void
reset_done (DConfAsyncResult *result,
            gpointer          user_data)
{
  struct asyncinfo *asi = user_data;

  asi->success = dconf_reset_finish (result,
                                     &asi->result.string,
                                     &asi->error);
  async_done (asi);
}

static gboolean
reset (gint           argc,
       gchar        **argv,
       gboolean       async,
       union result  *result,
       GError       **error)
{
  if (argc != 1 || !dconf_is_key (argv[0]))
    throw ("expected key");

  if (async)
    {
      struct asyncinfo asi;

      async_init (&asi);
      dconf_reset_async (argv[0], reset_done, &asi);
      return async_wait (&asi, result, error);
    }
  else
    return dconf_reset (argv[0], &result->string, error);
}

static void
set_locked_done (DConfAsyncResult *result,
                 gpointer          user_data)
{
  struct asyncinfo *asi = user_data;

  asi->success = dconf_set_locked_finish (result, &asi->error);
  async_done (asi);
}

static gboolean
set_locked (gint           argc,
            gchar        **argv,
            gboolean       async,
            union result  *result,
            GError       **error)
{
  gboolean lock;

  if (argc != 2 || !dconf_is_key (argv[0]) ||
      (strcmp (argv[1], "true") && strcmp (argv[1], "false")))
    throw ("expected one key and 'true' or 'false'");

  lock = strcmp (argv[1], "true") == 0;

  if (async)
    {
      struct asyncinfo asi;

      async_init (&asi);
      dconf_set_locked_async (argv[0], lock, set_locked_done, &asi);
      return async_wait (&asi, result, error);
    }
  else
    return dconf_set_locked (argv[0], lock, error);
}

static void
merge_done (DConfAsyncResult *result,
            gpointer          user_data)
{
  struct asyncinfo *asi = user_data;

  asi->success = dconf_merge_finish (result,
                                     &asi->result.string,
                                     &asi->error);
  async_done (asi);
}

static gboolean
merge (gint           argc,
       gchar        **argv,
       gboolean       async,
       union result  *result,
       GError       **error)
{
  gboolean success = FALSE;
  GTree *tree;
  gint i;

  if (argc < 3 || (argc & 1) == 0 || !dconf_is_path (argv[0]))
    throw ("expected a path, followed by relative-key/value pairs");

  tree = g_tree_new_full ((GCompareDataFunc) strcmp, NULL,
                          g_free, (GDestroyNotify) g_variant_unref);

  for (i = 1; i < argc; i += 2)
    {
      GVariant *value;

      if (!dconf_is_relative_key (argv[i]))
        {
          g_set_error (error, 0, 0,
                       "'%s' is not a relative key", argv[i]);
          break;
        }

      if ((value = g_variant_parse (argv[i + 1], -1, NULL, error)) == NULL)
        break;

      g_tree_insert (tree, g_strdup (argv[i]), value);
    }

  if (i == argc)
    {
      if (async)
        {
          struct asyncinfo asi;

          async_init (&asi);
          dconf_merge_async (argv[0], tree, merge_done, &asi);
          return async_wait (&asi, result, error);
        }
      else
        success = dconf_merge (argv[0], tree, &result->string, error);
    }

  g_tree_unref (tree);

  return success;
}

#define BOOL_RESULT     1
#define ASYNC           2
#define EVENT_ID        4

struct
{
  const gchar *command;
  guint flags;
  gboolean (*func) (int, char **, gboolean, union result *, GError **);
} commands[] = {
  { "is-key",           BOOL_RESULT,            is_key          },
  { "is-path",          BOOL_RESULT,            is_path         },
  { "is-key-or-path",   BOOL_RESULT,            is_key_or_path  },
  { "is-relative-key",  BOOL_RESULT,            is_relative_key },
  { "match",            BOOL_RESULT,            match           },
  { "get",              0,                      get             },
  { "list",             0,                      list            },
  { "get-writable",     BOOL_RESULT,            get_writable    },
  { "get-locked",       BOOL_RESULT,            get_locked      },
  { "set",              ASYNC | EVENT_ID,       set             },
  { "reset",            ASYNC | EVENT_ID,       reset           },
  { "set-locked",       ASYNC,                  set_locked      },
  { "merge",            ASYNC | EVENT_ID,       merge           }
};

int
main (int argc, char **argv)
{

  gboolean async = FALSE;
  gint opt, i;

  while ((opt = getopt_long (argc, argv, "+a", longopts, NULL)) >= 0)
    {
      switch (opt)
        {
        case '?':
          fprintf (stderr, "%s", usage_message);
          return 1;

        case 'h':
          printf ("%s", usage_message);
          printf ("%s", help_message);
          return 0;

        case 'v':
          printf ("dconf version " PACKAGE_VERSION "\n");
          return 0;

        case 'a':
          async = TRUE;
          break;

        default:
          g_assert_not_reached ();
        }
    }

  argv += optind;
  argc -= optind;

  if (argc == 0)
    {
      fprintf (stderr, "%s", usage_message);
      fprintf (stderr, "%s", help_message);
      return 1;
    }

  if (strcmp (argv[0], "help") == 0)
    {
      printf ("%s", usage_message);
      printf ("%s", help_message);
      return 0;
    }

  for (i = 0; i < G_N_ELEMENTS (commands); i++)
    if (strcmp (argv[0], commands[i].command) == 0)
      {
        GError *error = NULL;
        union result result;

        if (async && ~commands[i].flags & ASYNC)
          fprintf (stderr, "warning: --async has no effect for '%s'\n",
                   argv[0]);

        if (!commands[i].func (argc - 1, argv + 1, async, &result, &error))
          {
            fprintf (stderr, "dconf %s: %s\n", argv[0], error->message);
            g_error_free (error);

            return 1;
          }

        if (commands[i].flags & BOOL_RESULT)
          {
            g_print ("%s\n", result.boolean ? "true" : "false");
            return result.boolean ? 0 : 1;
          }

        else if (commands[i].flags & EVENT_ID)
          {
            g_print ("%s\n", result.string);
            return 0;
          }

        else
          return 0;

      }

  fprintf (stderr, "dconf: '%s' is not a dconf command."
                   "  See 'dconf --help'\n", argv[0]);
  return 1;
}
