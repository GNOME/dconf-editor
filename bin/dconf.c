#include <dconf.h>

const gchar *
shift (int *argc, char ***argv)
{
  if (argc == 0)
    return NULL;

  (*argc)--;
  return *(*argv)++;
}

const gchar *
peek (int argc, char **argv)
{
  if (argc == 0)
    return NULL;

  return *argv;
}

static gboolean
grab_args (int           argc,
           char        **argv,
           const gchar  *description,
           GError      **error,
           gint          num,
           ...)
{
  va_list ap;

  if (argc != num)
    {
      g_set_error (error, G_OPTION_ERROR, G_OPTION_ERROR_FAILED,
                   "require exactly %d arguments: %s", num, description);
      return FALSE;
    }

  va_start (ap, num);
  while (num--)
    *va_arg (ap, gchar **) = *argv++;
  va_end (ap);
}

static gboolean
ensure (const gchar  *type,
        const gchar  *string,
        gboolean    (*checker) (const gchar *string),
        GError      **error)
{
  if (!checker (string))
    {
      g_set_error (error, G_OPTION_ERROR, G_OPTION_ERROR_BAD_VALUE,
                   "'%s' is not a dconf %s", string, type);
      return FALSE;
    }

  return TRUE;
}

static gboolean
do_sync_command (DConfClient  *client,
                 int           argc,
                 char        **argv,
                 GError      **error)
{
  const gchar *cmd;

  cmd = shift (&argc, &argv);

  if (g_strcmp0 (cmd, "read") == 0)
    {
      const gchar *key;
      GVariant *value;
      gchar *printed;

      if (!grab_args (argc, argv, "key", error, 1, &key))
        return FALSE;

      if (!ensure ("key", key, dconf_is_key, error))
        return FALSE;

      value = dconf_client_read (client, key, DCONF_READ_NORMAL);

      if (value == NULL)
        return TRUE;

      printed = g_variant_print (value, TRUE);
      g_print ("%s\n", printed);
      g_variant_unref (value);
      g_free (printed);

      return TRUE;
    }

  else if (g_strcmp0 (cmd, "write") == 0)
    {
      const gchar *key, *strval;
      GVariant *value;

      if (!grab_args (argc, argv, "key and value", error, 2, &key, &strval))
        return FALSE;

      if (!ensure ("key", key, dconf_is_key, error))
        return FALSE;

      value = g_variant_parse (NULL, strval, NULL, NULL, error);

      if (value == NULL)
        return FALSE;

      return dconf_client_write (client, key, value, NULL, NULL, error);
    }

  else if (g_strcmp0 (cmd, "write-many") == 0)
    {
      g_assert_not_reached ();
    }

  else if (g_strcmp0 (cmd, "list") == 0)
    {
      const gchar *dir;
      gchar **list;

      if (!grab_args (argc, argv, "dir", error, 1, &dir))
        return FALSE;

      if (!ensure ("dir", dir, dconf_is_dir, error))
        return FALSE;

      list = dconf_client_list (client, dir, NULL);

      while (*list)
        g_print ("%s\n", *list++);

      return TRUE;
    }

  else if (g_strcmp0 (cmd, "lock") == 0)
    {
      const gchar *path;

      if (!grab_args (argc, argv, "path", error, 1, &path))
        return FALSE;

      if (!ensure ("path", path, dconf_is_path, error))
        return FALSE;

      return dconf_client_set_locked (client, path, TRUE);
    }

  else if (g_strcmp0 (cmd, "unlock") == 0)
    {
      const gchar *path;

      if (!grab_args (argc, argv, "path", error, 1, &path))
        return FALSE;

      if (!ensure ("path", path, dconf_is_path, error))
        return FALSE;

      return dconf_client_set_locked (client, path, FALSE);
    }

  else if (g_strcmp0 (cmd, "is-writable") == 0)
    {
      const gchar *path;

      if (!grab_args (argc, argv, "path", error, 1, &path))
        return FALSE;

      if (!ensure ("path", path, dconf_is_path, error))
        return FALSE;

      return dconf_client_is_writable (client, path, error);
    }
}

int
main (int argc, char **argv)
{
  GError *error = NULL;
  DConfClient *client;

  g_type_init ();
  g_set_prgname (shift (&argc, &argv));

  client = dconf_client_new (NULL, NULL, NULL, NULL);

  if (!do_sync_command (client, argc, argv, &error))
    g_error ("%s\n", error->message);

  return 0;
}
