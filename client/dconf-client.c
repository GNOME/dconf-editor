/*
 * Copyright © 2010 Codethink Limited
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
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "dconf-client.h"

#include "dconf-engine.h"
#include <glib-object.h>

struct _DConfClient
{
  GObject parent_instance;

  DConfEngine  *engine;
  GMainContext *context;
};

G_DEFINE_TYPE (DConfClient, dconf_client, G_TYPE_OBJECT)

enum
{
  SIGNAL_CHANGED,
  N_SIGNALS
};
static guint dconf_client_signals[N_SIGNALS];

static void
dconf_client_finalize (GObject *object)
{
  DConfClient *client = DCONF_CLIENT (object);

  dconf_engine_free (client->engine);
  g_main_context_unref (client->context);

  G_OBJECT_CLASS (dconf_client_parent_class)
    ->finalize (object);
}

static void
dconf_client_init (DConfClient *client)
{
}

static void
dconf_client_class_init (DConfClientClass *class)
{
  class->finalize = dconf_client_finalize;

  dconf_client_signals[SIGNAL_CHANGED] = g_signal_new ("changed", DCONF_TYPE_CLIENT, G_SIGNAL_RUN_LAST,
                                                       0, NULL, NULL, NULL, G_TYPE_NONE, 3,
                                                       G_TYPE_STRING | G_SIGNAL_TYPE_STATIC_SCOPE,
                                                       G_TYPE_STRV | G_SIGNAL_TYPE_STATIC_SCOPE,
                                                       G_TYPE_STRING | G_SIGNAL_TYPE_STATIC_SCOPE);
}

typedef struct
{
  DConfClient  *client;
  gchar        *prefix;
  gchar       **changes;
  gchar        *tag;
} DConfClientChange;

static gboolean
dconf_client_dispatch_change_signal (gpointer user_data)
{
  DConfClientChange *change = user_data;

  g_signal_emit (change->client, dconf_client_signals[SIGNAL_CHANGED], 0,
                 change->prefix, change->changes, change->tag);

  g_object_unref (change->client);
  g_free (change->prefix);
  g_strfreev (change->changes);
  g_free (change->tag);
  g_slice_free (DConfClientChange, change);

  return G_SOURCE_REMOVE;
}

void
dconf_engine_change_notify (DConfEngine         *engine,
                            const gchar         *prefix,
                            const gchar * const *changes,
                            const gchar *        tag,
                            gpointer             user_data)
{
  DConfClient *client = user_data;
  DConfClientChange *change;

  g_return_if_fail (DCONF_IS_CLIENT (client));

  change = g_slice_new (DConfClientChange);
  change->client = g_object_ref (client);
  change->prefix = g_strdup (prefix);
  change->changes = g_strdupv ((gchar **) changes);
  change->tag = g_strdup (tag);

  g_main_context_invoke (client->context, dconf_client_dispatch_change_signal, change);
}

DConfClient *
dconf_client_new (void)
{
  DConfClient *client;

  client = g_object_new (DCONF_TYPE_CLIENT, NULL);
  client->engine = dconf_engine_new (client);
  client->context = g_main_context_ref_thread_default ();

  return client;
}

GVariant *
dconf_client_read (DConfClient *client,
                   const gchar *key)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), NULL);

  return dconf_engine_read (client->engine, NULL, key);
}

gchar **
dconf_client_list (DConfClient *client,
                   const gchar *dir,
                   gint        *length)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), NULL);

  return dconf_engine_list (client->engine, dir, length);
}

gboolean
dconf_client_is_writable (DConfClient *client,
                          const gchar *key)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  return dconf_engine_is_writable (client->engine, key);
}

gboolean
dconf_client_write_fast (DConfClient  *client,
                         const gchar  *key,
                         GVariant     *value,
                         GError      **error)
{
  DConfChangeset *changeset;
  gboolean success;

  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  changeset = dconf_changeset_new_write (key, value);
  success = dconf_engine_change_fast (client->engine, changeset, error);
  dconf_changeset_unref (changeset);

  return success;
}

gboolean
dconf_client_write_sync (DConfClient   *client,
                         const gchar   *key,
                         GVariant      *value,
                         gchar        **tag,
                         GCancellable  *cancellable,
                         GError       **error)
{
  DConfChangeset *changeset;
  gboolean success;

  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  changeset = dconf_changeset_new_write (key, value);
  success = dconf_engine_change_sync (client->engine, changeset, tag, error);
  dconf_changeset_unref (changeset);

  return success;
}

gboolean
dconf_client_change_fast (DConfClient     *client,
                          DConfChangeset  *changeset,
                          GError         **error)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  return dconf_engine_change_fast (client->engine, changeset, error);
}

gboolean
dconf_client_change_sync (DConfClient     *client,
                          DConfChangeset  *changeset,
                          gchar          **tag,
                          GCancellable    *cancellable,
                          GError         **error)
{
  g_return_val_if_fail (DCONF_IS_CLIENT (client), FALSE);

  return dconf_engine_change_sync (client->engine, changeset, tag, error);
}

void
dconf_client_watch_fast (DConfClient *client,
                         const gchar *path)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_watch_fast (client->engine, path);
}

void
dconf_client_watch_sync (DConfClient *client,
                         const gchar *path)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_watch_sync (client->engine, path);
}

void
dconf_client_unwatch_fast (DConfClient *client,
                           const gchar *path)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_unwatch_fast (client->engine, path);
}

void
dconf_client_unwatch_sync (DConfClient *client,
                           const gchar *path)
{
  g_return_if_fail (DCONF_IS_CLIENT (client));

  dconf_engine_unwatch_sync (client->engine, path);
}
