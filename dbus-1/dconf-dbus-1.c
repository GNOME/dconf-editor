/**
 * Copyright © 2010 Canonical Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the licence, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 **/

#include "config.h"

#include "dconf-dbus-1.h"

#include "../engine/dconf-engine.h"
#include "dconf-libdbus-1.h"

#include <string.h>

struct _DConfDBusClient
{
  DConfEngine *engine;
  GSList *watches;
  gint ref_count;
};

typedef struct
{
  gchar           *path;
  DConfDBusNotify  notify;
  gpointer         user_data;
} Watch;

void
dconf_engine_change_notify (DConfEngine         *engine,
                            const gchar         *prefix,
                            const gchar * const *changes,
                            const gchar         *tag,
                            gboolean             is_writability,
                            gpointer             origin_tag,
                            gpointer             user_data)
{
  DConfDBusClient *dcdbc = user_data;
  gchar **my_changes;
  gint n_changes;
  GSList *iter;
  gint i;

  n_changes = g_strv_length ((gchar **) changes);
  my_changes = g_new (gchar *, n_changes + 1);

  for (i = 0; i < n_changes; i++)
    my_changes[i] = g_strconcat (prefix, changes[i], NULL);
  my_changes[i] = NULL;

  for (iter = dcdbc->watches; iter; iter = iter->next)
    {
      Watch *watch = iter->data;

      for (i = 0; i < n_changes; i++)
        if (g_str_has_prefix (my_changes[i], watch->path))
          watch->notify (dcdbc, my_changes[i], watch->user_data);
    }

  g_strfreev (my_changes);
}

GVariant *
dconf_dbus_client_read (DConfDBusClient *dcdbc,
                        const gchar     *key)
{
  return dconf_engine_read (dcdbc->engine, NULL, key);
}

gboolean
dconf_dbus_client_write (DConfDBusClient *dcdbc,
                         const gchar     *key,
                         GVariant        *value)
{
  DConfChangeset *changeset;
  gboolean success;

  changeset = dconf_changeset_new_write (key, value);
  success = dconf_engine_change_fast (dcdbc->engine, changeset, NULL, NULL);
  dconf_changeset_unref (changeset);

  return success;
}

void
dconf_dbus_client_subscribe (DConfDBusClient *dcdbc,
                             const gchar     *path,
                             DConfDBusNotify  notify,
                             gpointer         user_data)
{
  Watch *watch;

  watch = g_slice_new (Watch);
  watch->path = g_strdup (path);
  watch->notify = notify;
  watch->user_data = user_data;

  dcdbc->watches = g_slist_prepend (dcdbc->watches, watch);

  dconf_engine_watch_fast (dcdbc->engine, path);
}

void
dconf_dbus_client_unsubscribe (DConfDBusClient *dcdbc,
                               DConfDBusNotify  notify,
                               gpointer         user_data)
{
  GSList **ptr;

  for (ptr = &dcdbc->watches; *ptr; ptr = &(*ptr)->next)
    {
      Watch *watch = (*ptr)->data;

      if (watch->notify == notify && watch->user_data == user_data)
        {
          *ptr = g_slist_remove_link (*ptr, *ptr);
          dconf_engine_unwatch_fast (dcdbc->engine, watch->path);
          g_free (watch->path);
          g_slice_free (Watch, watch);
          return;
        }
    }

  g_warning ("No matching watch found to unsubscribe");
}

gboolean
dconf_dbus_client_has_pending (DConfDBusClient *dcdbc)
{
  return dconf_engine_has_outstanding (dcdbc->engine);
}

DConfDBusClient *
dconf_dbus_client_new (const gchar    *profile,
                       DBusConnection *session,
                       DBusConnection *system)
{
  DConfDBusClient *dcdbc;

  if (session == NULL)
    session = dbus_bus_get (DBUS_BUS_SESSION, NULL);

  if (system == NULL)
    system = dbus_bus_get (DBUS_BUS_SYSTEM, NULL);

  dconf_libdbus_1_provide_bus (G_BUS_TYPE_SESSION, session);
  dconf_libdbus_1_provide_bus (G_BUS_TYPE_SYSTEM, system);

  dcdbc = g_slice_new (DConfDBusClient);
  dcdbc->engine = dconf_engine_new (NULL, dcdbc, NULL);
  dcdbc->watches = NULL;
  dcdbc->ref_count = 1;

  return dcdbc;
}

void
dconf_dbus_client_unref (DConfDBusClient *dcdbc)
{
  if (--dcdbc->ref_count == 0)
    {
      g_return_if_fail (dcdbc->watches == NULL);

      g_slice_free (DConfDBusClient, dcdbc);
    }
}

DConfDBusClient *
dconf_dbus_client_ref (DConfDBusClient *dcdbc)
{
  dcdbc->ref_count++;

  return dcdbc;
}
