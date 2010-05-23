#include <dconf.h>

int
main (int argc, char **argv)
{
  DConfClient *client;

  g_type_init ();

  client = dconf_client_new (NULL, NULL, NULL, NULL);

  if (g_strcmp0 (argv[1], "get") == 0)
    {
      GVariant *value;

      value = dconf_client_read (client, argv[2], DCONF_READ_NORMAL);

      if (value == NULL)
        g_print ("(null)\n");
      else
        {
          gchar *printed;
          printed = g_variant_print (value, TRUE);
          g_print ("%s\n", printed);
          g_variant_unref (value);
          g_free (printed);
        }
    }

  else if (g_strcmp0 (argv[1], "set") == 0)
    {
      GError *error = NULL;
      GVariant *value;

      value = g_variant_parse (NULL, argv[3], NULL, NULL, &error);

      if (value == NULL)
        g_error ("%s\n", error->message);

      if (!dconf_client_write (client, argv[2], value, NULL, NULL, &error))
        g_error ("%s\n", error->message);
    }

  return 0;
}
