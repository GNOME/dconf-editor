#include "dconf-writer.h"
#include <string.h>
#include <gbus.h>

static DConfWriter *writer;

static gboolean
dconf_service_handler (GBus              *bus,
                       const GBusMessage *message,
                       gpointer           user_data)
{
  DConfWriter *writer = user_data;

  if (g_bus_message_is_call (message, "ca.desrt.dconf", "Set", "sv"))
    {
      const gchar *key;
      GVariant *value;

      g_bus_message_get (message, "sv", &key, &value);
      dconf_writer_set (writer, key, value);
      g_variant_unref (value);

      g_bus_emit (G_BUS_SESSION,
                  g_bus_message_get_path (message),
                  "ca.desrt.dconf", "Notify", "s", key);

      return g_bus_return (message, "");
    }

  if (g_bus_message_is_call (message, "ca.desrt.dconf", "Get", "s"))
    {
      const gchar *key;
      gchar *str;

      g_bus_message_get (message, "s", &key);
      str = g_strdup_printf ("Fake result for key '%s'", key);
      g_bus_return (message, "v", g_variant_new_string (str));
      g_free (str);

      return TRUE;
    }

  if (g_bus_message_is_call (message,
                             "org.freedesktop.DBus.Introspectable",
                             "Introspect", ""))
    return g_bus_return (message, "s",
      "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Intros"
      "pection 1.0//EN\" \"http://www.freedesktop.org/standards/dbus/1"
      ".0/introspect.dtd\">\n"
      "<node>\n"
      "  <interface name='org.freedesktop.DBus.Introspectable'>\n"
      "    <method name='Introspect'>\n"
      "      <arg name='data' direction='out' type='s'/>\n"
      "    </method>\n"
      "  </interface>\n"
      "  <interface name='ca.desrt.dconf'>\n"
      "    <method name='Set'>\n"
      "      <arg name='key' direction='in' type='s'/>\n"
      "      <arg name='value' direction='in' type='v'/>\n"
      "    </method>\n"
      "  </interface>\n"
      "</node>");

  return FALSE;
}

int
main (void)
{
  const gchar *config_dir;
  GBusRemote *bus;
  gchar *file;

  config_dir = g_get_user_config_dir ();
  file = g_strdup_printf ("%s/dconf.db", config_dir);

  writer = dconf_writer_new (file);

  bus = g_bus_remote_new (G_BUS_SESSION,
                          "org.freedesktop.DBus",
                          "/org/freedesktop/DBus",
                          "org.freedesktop.DBus");
  g_bus_remote_call (bus, "RequestName", NULL, "su", "u", "ca.desrt.dconf", 0, NULL);
  g_bus_register_object (G_BUS_SESSION, "/user", dconf_service_handler, writer);

  g_main_loop_run (g_main_loop_new (NULL, FALSE));

  return 0;
}
