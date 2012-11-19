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

#include "../engine/dconf-engine.h"

/* We interact with GDBus using a worker thread just for dconf.
 *
 * We want to have a worker thread that's not the main thread for one
 * main reason: we don't want to have all of our incoming signals and
 * method call replies being delivered via the default main context
 * (which may blocked or simply not running at all).
 *
 * The only question is if we should have our own thread or share the
 * GDBus worker thread.  This file takes the approach that we should
 * have our own thread.  See "dconf-gdbus-filter.c" for an approach that
 * shares the worker thread with GDBus.
 *
 * We gain at least one advantage here that we cannot gain any other way
 * (including sharing a worker thread with GDBus): fast startup.
 *
 * The first thing that happens when GSettings comes online is a D-Bus
 * call to establish a watch.  We have to bring up the GDBusConnection.
 * There are two ways to do that: sync and async.
 *
 * We can't do either of those in GDBus's worker thread (since it
 * doesn't exist yet).  We can't do async in the main thread because the
 * user may not be running the mainloop (as is the case for the
 * commandline tool, for example).
 *
 * That leaves only one option: synchronous initialisation in the main
 * thread.  That's what the "dconf-gdbus-filter" variant of this code
 * does, and it's slower because of it.
 *
 * If we have our own worker thread then we can punt synchronous
 * initialisation of the bus to it and return immediately.
 *
 * We also gain the advantage that the dconf worker thread and the GDBus
 * worker thread can both be doing work at the same time.  This
 * advantage is probably quite marginal (and is likely outweighed by the
 * cost of all the punting around of messages between threads).
 */

typedef struct
{
  GBusType               bus_type;
  const gchar           *bus_name;
  const gchar           *object_path;
  const gchar           *interface_name;
  const gchar           *method_name;
  GVariant              *parameters;
  DConfEngineCallHandle *handle;
} DConfGDBusCall;

static gpointer
dconf_gdbus_worker_thread (gpointer user_data)
{
  GMainContext *context = user_data;

  g_main_context_push_thread_default (context);

  for (;;)
    g_main_context_iteration (context, TRUE);

  /* srsly, gcc? */
  return NULL;
}

static GMainContext *
dconf_gdbus_get_worker_context (void)
{
  static GMainContext *worker_context;

  if (g_once_init_enter (&worker_context))
    {
      GMainContext *context;

      context = g_main_context_new ();
      g_thread_new ("dconf worker", dconf_gdbus_worker_thread, context);
      g_once_init_leave (&worker_context, context);
    }

  return worker_context;
}

static void
dconf_gdbus_signal_handler (GDBusConnection *connection,
                            const gchar     *sender_name,
                            const gchar     *object_path,
                            const gchar     *interface_name,
                            const gchar     *signal_name,
                            GVariant        *parameters,
                            gpointer         user_data)
{
  GBusType bus_type = GPOINTER_TO_INT (user_data);

  dconf_engine_handle_dbus_signal (bus_type, sender_name, object_path, signal_name, parameters);
}

/* The code to create and initialise the GDBusConnection for a
 * particular bus type is more complicated than it should be.
 *
 * The complication comes from the fact that we must call
 * g_dbus_connection_signal_subscribe() from the thread in which the
 * signal handler will run (which in our case is the worker thread).
 * g_main_context_push_thread_default() attempts to acquire the context,
 * preventing us from temporarily pushing the worker's context just for
 * the sake of setting up the subscription.
 *
 * We therefore always create the bus connection from the worker thread.
 * For requests that are already in the worker thread this is a pretty
 * simple affair.
 *
 * For requests in other threads (ie: synchronous calls) we have to poke
 * the worker to instantiate the bus for us (if it doesn't already
 * exist).  We do that by using g_main_context_invoke() to schedule a
 * dummy request in the worker and then we wait on a GCond until we see
 * that the bus has been created.
 *
 * An attempt to get a particular bus can go one of two ways:
 *
 *   - success: we end up with a GDBusConnection.
 *
 *   - failure: we end up with a GError.
 *
 * One way or another we put the result in dconf_gdbus_get_bus_data[] so
 * that we only have one pointer value to check.  We know what type of
 * result it is by dconf_gdbus_get_bus_is_error[].
 */

static GMutex   dconf_gdbus_get_bus_lock;
static GCond    dconf_gdbus_get_bus_cond;
static gpointer dconf_gdbus_get_bus_data[5];
static gboolean dconf_gdbus_get_bus_is_error[5];

static GDBusConnection *
dconf_gdbus_get_bus_common (GBusType       bus_type,
                            const GError **error)
{
  if (dconf_gdbus_get_bus_is_error[bus_type])
    {
      if (error)
        *error = dconf_gdbus_get_bus_data[bus_type];

      return NULL;
    }

  return dconf_gdbus_get_bus_data[bus_type];
}

static GDBusConnection *
dconf_gdbus_get_bus_in_worker (GBusType       bus_type,
                               const GError **error)
{
  g_assert_cmpint (bus_type, <, G_N_ELEMENTS (dconf_gdbus_get_bus_data));

  /* We're in the worker thread and only the worker thread can ever set
   * this variable so there is no need to take a lock.
   */
  if (dconf_gdbus_get_bus_data[bus_type] == NULL)
    {
      GDBusConnection *connection;
      GError *error = NULL;
      gpointer result;

      connection = g_bus_get_sync (bus_type, NULL, &error);

      if (connection)
        {
          g_dbus_connection_signal_subscribe (connection, NULL, "ca.desrt.dconf.Writer",
                                              NULL, NULL, NULL, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
                                              dconf_gdbus_signal_handler, GINT_TO_POINTER (bus_type), NULL);
          dconf_gdbus_get_bus_is_error[bus_type] = FALSE;
          result = connection;
        }
      else
        {
          dconf_gdbus_get_bus_is_error[bus_type] = TRUE;
          result = error;
        }

      g_assert (result != NULL);

      /* It's possible that another thread was waiting for us to do
       * this on its behalf.  Wake it up.
       *
       * The other thread cannot actually wake up until we release the
       * mutex below so we have a guarantee that this CPU will have
       * flushed all outstanding writes.  The other CPU has to acquire
       * the lock so it cannot have done any out-of-order reads either.
       */
      g_mutex_lock (&dconf_gdbus_get_bus_lock);
      dconf_gdbus_get_bus_data[bus_type] = result;
      g_cond_broadcast (&dconf_gdbus_get_bus_cond);
      g_mutex_unlock (&dconf_gdbus_get_bus_lock);
    }

  return dconf_gdbus_get_bus_common (bus_type, error);
}

static void
dconf_gdbus_method_call_done (GObject      *source,
                              GAsyncResult *result,
                              gpointer      user_data)
{
  GDBusConnection *connection = G_DBUS_CONNECTION (source);
  DConfEngineCallHandle *handle = user_data;
  GError *error = NULL;
  GVariant *reply;

  reply = g_dbus_connection_call_finish (connection, result, &error);
  dconf_engine_call_handle_reply (handle, reply, error);
  g_clear_pointer (&reply, g_variant_unref);
  g_clear_error (&error);
}

static gboolean
dconf_gdbus_method_call (gpointer user_data)
{
  DConfGDBusCall *call = user_data;
  GDBusConnection *connection;
  const GError *error = NULL;

  connection = dconf_gdbus_get_bus_in_worker (call->bus_type, &error);

  if (connection)
    g_dbus_connection_call (connection, call->bus_name, call->object_path, call->interface_name,
                            call->method_name, call->parameters, NULL, G_DBUS_CALL_FLAGS_NONE,
                            -1, NULL, dconf_gdbus_method_call_done, call->handle);

  else
    dconf_engine_call_handle_reply (call->handle, NULL, error);

  g_variant_unref (call->parameters);
  g_slice_free (DConfGDBusCall, call);

  return FALSE;
}

gboolean
dconf_engine_dbus_call_async_func (GBusType                bus_type,
                                   const gchar            *bus_name,
                                   const gchar            *object_path,
                                   const gchar            *interface_name,
                                   const gchar            *method_name,
                                   GVariant               *parameters,
                                   DConfEngineCallHandle  *handle,
                                   GError                **error)
{
  DConfGDBusCall *call;
  GSource *source;

  call = g_slice_new (DConfGDBusCall);
  call->bus_type = bus_type;
  call->bus_name = bus_name;
  call->object_path = object_path;
  call->interface_name = interface_name;
  call->method_name = method_name;
  call->parameters = g_variant_ref_sink (parameters);
  call->handle = handle;

  source = g_idle_source_new ();
  g_source_set_callback (source, dconf_gdbus_method_call, call, NULL);
  g_source_attach (source, dconf_gdbus_get_worker_context ());
  g_source_unref (source);

  return TRUE;
}

/* Dummy function to force the bus into existence in the worker. */
static gboolean
dconf_gdbus_summon_bus (gpointer user_data)
{
  GBusType bus_type = GPOINTER_TO_INT (user_data);

  dconf_gdbus_get_bus_in_worker (bus_type, NULL);

  return G_SOURCE_REMOVE;
}

static GDBusConnection *
dconf_gdbus_get_bus_for_sync (GBusType       bus_type,
                              const GError **error)
{
  g_assert_cmpint (bus_type, <, G_N_ELEMENTS (dconf_gdbus_get_bus_data));

  /* I'm not 100% sure we have to lock as much as we do here, but let's
   * play it safe.
   *
   * This codepath is only hit on synchronous calls anyway.  You're
   * probably not doing those if you care a lot about performance.
   */
  g_mutex_lock (&dconf_gdbus_get_bus_lock);
  if (dconf_gdbus_get_bus_data[bus_type] == NULL)
    {
      g_main_context_invoke (dconf_gdbus_get_worker_context (),
                             dconf_gdbus_summon_bus,
                             GINT_TO_POINTER (bus_type));

      while (dconf_gdbus_get_bus_data[bus_type] == NULL)
        g_cond_wait (&dconf_gdbus_get_bus_cond, &dconf_gdbus_get_bus_lock);
    }
  g_mutex_unlock (&dconf_gdbus_get_bus_lock);

  return dconf_gdbus_get_bus_common (bus_type, error);
}

GVariant *
dconf_engine_dbus_call_sync_func (GBusType             bus_type,
                                  const gchar         *bus_name,
                                  const gchar         *object_path,
                                  const gchar         *interface_name,
                                  const gchar         *method_name,
                                  GVariant            *parameters,
                                  const GVariantType  *reply_type,
                                  GError             **error)
{
  const GError *inner_error = NULL;
  GDBusConnection *connection;

  connection = dconf_gdbus_get_bus_for_sync (bus_type, &inner_error);

  if (connection == NULL)
    {
      g_variant_unref (g_variant_ref_sink (parameters));

      if (error)
        *error = g_error_copy (inner_error);

      return NULL;
    }

  return g_dbus_connection_call_sync (connection, bus_name, object_path, interface_name, method_name,
                                      parameters, reply_type, G_DBUS_CALL_FLAGS_NONE, -1, NULL, error);
}

#ifndef PIC
void
dconf_engine_dbus_init_for_testing (void)
{
}
#endif
