#include <dconf.h>

int
main (int argc, char **argv)
{
  DConfClient *client;
  GVariant *value;

  g_type_init ();

  client = dconf_client_new (NULL, NULL, NULL, NULL);

  value = dconf_client_read (client, argv[1], DCONF_READ_NORMAL);

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

  return 0;
}
