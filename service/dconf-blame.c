/*
 * Copyright © 2012 Canonical Limited
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

#include "dconf-blame.h"

#include "dconf-generated.h"

#include <string.h>
#include <stdlib.h>
#include <fcntl.h>

typedef DConfDBusServiceInfoSkeletonClass DConfBlameClass;
struct _DConfBlame
{
  DConfDBusServiceInfoSkeleton parent_instance;

  GString *blame_info;
};

static void dconf_blame_iface_init (DConfDBusServiceInfoIface *iface);
G_DEFINE_TYPE_WITH_CODE (DConfBlame, dconf_blame, DCONF_DBUS_TYPE_SERVICE_INFO_SKELETON,
                         G_IMPLEMENT_INTERFACE (DCONF_DBUS_TYPE_SERVICE_INFO, dconf_blame_iface_init))

#include "../common/dconf-changeset.h"
#include "dconf-writer.h"

void
dconf_blame_record (GDBusMethodInvocation *invocation)
{
  DConfBlame *blame = dconf_blame_get ();
  GError *error = NULL;
  GVariant *parameters;
  GVariant *reply;
  GString *info;

  if (!blame)
    return;

  if (blame->blame_info->len)
    g_string_append (blame->blame_info, "\n====================================================================\n");

  info = blame->blame_info;

  g_string_append_printf (info, "Sender: %s\n", g_dbus_method_invocation_get_sender (invocation));
  g_string_append_printf (info, "Object path: %s\n", g_dbus_method_invocation_get_object_path (invocation));
  g_string_append_printf (info, "Method: %s\n", g_dbus_method_invocation_get_method_name (invocation));

  if ((parameters = g_dbus_method_invocation_get_parameters (invocation)))
    {
      gchar *tmp;

      tmp = g_variant_print (parameters, FALSE);
      g_string_append_printf (info, "Parameters: %s\n", tmp);
      g_free (tmp);
    }

  reply = g_dbus_connection_call_sync (g_dbus_method_invocation_get_connection (invocation),
                                       "org.freedesktop.DBus", "/", "org.freedesktop.DBus",
                                       "GetConnectionUnixProcessID",
                                       g_variant_new ("(s)", g_dbus_method_invocation_get_sender (invocation)),
                                       G_VARIANT_TYPE ("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);

  if (reply != NULL)
    {
      guint pid;

      g_variant_get (reply, "(u)", &pid);
      g_string_append_printf (info, "PID: %u\n", pid);
      g_variant_unref (reply);
    }
  else
    {
      g_string_append_printf (info, "Unable to acquire PID: %s\n", error->message);
      g_error_free (error);
    }

  {
    const gchar * const ps_fx[] = { "ps", "fx", NULL };
    gchar *result_out;
    gchar *result_err;
    gint status;

    if (g_spawn_sync (NULL, (gchar **) ps_fx, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL,
                      &result_out, &result_err, &status, &error))
      {
        g_string_append (info, "\n=== Process table from time of call follows ('ps fx') ===\n");
        g_string_append (info, result_out);
        g_string_append (info, result_err);
        g_string_append_printf (info, "\nps exit status: %u\n", status);
      }
    else
      {
        g_string_append_printf (info, "\nUnable to spawn 'ps fx': %s\n", error->message);
        g_error_free (error);
      }
  }
}

static gboolean
dconf_blame_handle_blame (DConfDBusServiceInfo  *info,
                          GDBusMethodInvocation *invocation)
{
  DConfBlame *blame = DCONF_BLAME (info);

  dconf_blame_record (invocation);

  g_dbus_method_invocation_return_value (invocation, g_variant_new ("(s)", blame->blame_info->str));

  return TRUE;
}

static void
dconf_blame_init (DConfBlame *blame)
{
  blame->blame_info = g_string_new (NULL);
}

static void
dconf_blame_class_init (DConfBlameClass *class)
{
}

static void
dconf_blame_iface_init (DConfDBusServiceInfoIface *iface)
{
  iface->handle_blame = dconf_blame_handle_blame;
}

static gboolean
dconf_blame_enabled (void)
{
  gint fd;

  if (getenv ("DCONF_BLAME"))
    return TRUE;

  fd = open ("/proc/cmdline", O_RDONLY);
  if (fd != -1)
    {
      gchar buffer[1024];
      gssize s;

      s = read (fd, buffer, sizeof buffer - 1);
      close (fd);

      if (0 < s && s < sizeof buffer)
        {
          buffer[s] = '\0';
          if (strstr (buffer, "DCONF_BLAME"))
            return TRUE;
        }
    }

  return FALSE;
}

DConfBlame *
dconf_blame_get (void)
{
  static DConfBlame *blame;
  static gboolean checked;

  if (!checked)
    {
      if (dconf_blame_enabled ())
        blame = g_object_new (DCONF_TYPE_BLAME, NULL);

      checked = TRUE;
    }

  return blame;
}
