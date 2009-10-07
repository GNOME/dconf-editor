#include <stdio.h>
#include <dconf.h>
#include <getopt.h>
#include <glib.h>
#include <string.h>

static const char usage_message[] =
"usage: dconf [--version] [--async] [--help] COMMAND [ARGS]\n";

static const char help_message[] =
"\n"
"The valid commands are:\n"
"   is-key              check if a string is a valid dconf key\n"
"   is-path             check if a string is a valid dconf path\n"
"   is-key-or-path      check if a string is a valid dconf key or path\n"
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

static gboolean
is_key (gint       argc,
        gchar    **argv,
        gboolean   async)
{
  gboolean result;

  if (argc != 1)
    {
      fprintf (stderr, "dconf is-key: expected one string to check\n");
      return FALSE;
    }

  result = dconf_is_key (argv[0]);
  g_print ("%s\n", result ? "true" : "false");

  return result;
}

static gboolean
is_path (gint       argc,
         gchar    **argv,
         gboolean   async)
{
  gboolean result;

  if (argc != 1)
    {
      fprintf (stderr, "dconf is-path: expected one string to check\n");
      return FALSE;
    }

  result = dconf_is_path (argv[0]);
  g_print ("%s\n", result ? "true" : "false");

  return result;
}

static gboolean
is_key_or_path (gint       argc,
                gchar    **argv,
                gboolean   async)
{
  gboolean result;

  if (argc != 1)
    {
      fprintf (stderr, "dconf is-key-or-path: expected one string to check\n");
      return FALSE;
    }

  result = dconf_is_key_or_path (argv[0]);
  g_print ("%s\n", result ? "true" : "false");

  return result;
}

static gboolean
match (gint       argc,
       gchar    **argv,
       gboolean   async)
{
  gboolean result;

  if (argc != 2)
    {
      fprintf (stderr, "dconf match: expected two strings to check\n");
      return FALSE;
    }

  result = dconf_match (argv[0], argv[1]);
  g_print ("%s\n", result ? "true" : "false");

  return result;
}

static gboolean
get (gint       argc,
     gchar    **argv,
     gboolean   async)
{
  GVariant *value;

  if (argc != 1 || !dconf_is_key (argv[0]))
    {
      fprintf (stderr, "dconf get: expected key\n");
      return FALSE;
    }

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
list (gint       argc,
      gchar    **argv,
      gboolean   async)
{
  gchar **list;
  gint i;

  if (argc != 1 || !dconf_is_path (argv[0]))
    {
      fprintf (stderr, "dconf list: expected path\n");
      return FALSE;
    }

  list = dconf_list (argv[0], NULL);

  for (i = 0; list[i]; i++)
    g_print ("%s\n", list[i]);

  g_strfreev (list);

  return i > 0;
}

static gboolean
get_writable (gint       argc,
              gchar    **argv,
              gboolean   async)
{
  gboolean result;

  if (argc != 1 || !dconf_is_key_or_path (argv[0]))
    {
      fprintf (stderr, "dconf get-writable: expected key or path\n");
      return FALSE;
    }

  result = dconf_get_writable (argv[0]);
  g_print ("%s\n", result ? "true" : "false");

  return result;
}

static gboolean
get_locked (gint       argc,
            gchar    **argv,
            gboolean   async)
{
  gboolean result;

  if (argc != 1 || !dconf_is_key_or_path (argv[0]))
    {
      fprintf (stderr, "dconf get-locked: expected key or path\n");
      return FALSE;
    }

  result = dconf_get_locked (argv[0]);
  g_print ("%s\n", result ? "true" : "false");

  return result;
}

static gboolean
set (gint       argc,
     gchar    **argv,
     gboolean   async)
{
  fprintf (stderr, "not yet implemented\n");
  return FALSE;
}

static gboolean
reset (gint       argc,
       gchar    **argv,
       gboolean   async)
{
  fprintf (stderr, "not yet implemented\n");
  return FALSE;
}

static gboolean
set_locked (gint       argc,
            gchar    **argv,
            gboolean   async)
{
  fprintf (stderr, "not yet implemented\n");
  return FALSE;
}

static gboolean
merge (gint       argc,
       gchar    **argv,
       gboolean   async)
{
  fprintf (stderr, "not yet implemented\n");
  return FALSE;
}

struct
{
  const gchar *command;
  gboolean async_meaningful;
  gboolean (*func) (int argc, char **argv, gboolean async);
} commands[] = {
  { "is-key",           FALSE,  is_key          },
  { "is-path",          FALSE,  is_path         },
  { "is-key-or-path",   FALSE,  is_key_or_path  },
  { "match",            FALSE,  match           },
  { "get",              FALSE,  get             },
  { "list",             FALSE,  list            },
  { "get-writable",     FALSE,  get_writable    },
  { "get-locked",       FALSE,  get_locked      },
  { "set",              TRUE,   set             },
  { "reset",            TRUE,   reset           },
  { "set-locked",       TRUE,   set_locked      },
  { "merge",            TRUE,   merge           }
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
        if (async && !commands[i].async_meaningful)
          fprintf (stderr, "warning: --async has no effect for '%s'\n",
                   argv[0]);

        return !commands[i].func (argc - 1, argv + 1, async);
      }

  fprintf (stderr, "dconf: '%s' is not a dconf command."
                   "  See 'dconf --help'\n", argv[0]);
  return 1;
}
