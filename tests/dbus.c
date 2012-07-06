#include <string.h>
#include <glib.h>
#include <stdlib.h>

/* Test the DBus communicaton code.
 */

#include "dconf-engine.h"

static gboolean okay_in_main;
static GThread *main_thread;
static GThread *dbus_thread;
static GQueue   async_call_success_queue;
static GQueue   async_call_error_queue;
static GMutex   async_call_queue_lock;
static GCond    async_call_queue_cond;
static gboolean signal_was_received;

void
dconf_engine_call_handle_reply (DConfEngineCallHandle *handle,
                                GVariant              *parameters,
                                const GError          *error)
{
  DConfEngineCallHandle *expected_handle;

  /* Ensure that messages are never delivered in the main thread except
   * by way of a mainloop (ie: not during sync calls).
   *
   * It's okay if they are delivered in another thread at the same time
   * as a sync call is happening in the main thread, though...
   */
  g_assert (g_thread_self () != main_thread || okay_in_main);

  /* Make sure that we only ever receive D-Bus calls from a single
   * thread.
   */
  if (!dbus_thread)
    dbus_thread = g_thread_self ();
  g_assert (g_thread_self () == dbus_thread);

  /* This is the passing case. */
  if (parameters != NULL)
    {
      g_mutex_lock (&async_call_queue_lock);
      g_assert (g_queue_is_empty (&async_call_error_queue));
      expected_handle = g_queue_pop_head (&async_call_success_queue);
      g_mutex_unlock (&async_call_queue_lock);

      g_assert (parameters != NULL);
      g_assert (error == NULL);
      g_assert (g_variant_is_of_type (parameters, G_VARIANT_TYPE ("(s)")));

      g_assert (expected_handle == handle);
      g_free (handle);

      g_mutex_lock (&async_call_queue_lock);
      if (g_queue_is_empty (&async_call_success_queue))
        g_cond_broadcast (&async_call_queue_cond);
      g_mutex_unlock (&async_call_queue_lock);
    }
  else
    {
      g_mutex_lock (&async_call_queue_lock);
      g_assert (g_queue_is_empty (&async_call_success_queue));
      expected_handle = g_queue_pop_head (&async_call_error_queue);
      g_mutex_unlock (&async_call_queue_lock);

      g_assert (parameters == NULL);
      g_assert (error != NULL);

      g_assert (expected_handle == handle);
      g_free (handle);

      g_mutex_lock (&async_call_queue_lock);
      if (g_queue_is_empty (&async_call_error_queue))
        g_cond_broadcast (&async_call_queue_cond);
      g_mutex_unlock (&async_call_queue_lock);
    }
}

void
dconf_engine_handle_dbus_signal (GBusType     bus_type,
                                 const gchar *bus_name,
                                 const gchar *object_path,
                                 const gchar *signal_name,
                                 GVariant    *parameters)
{
  g_assert (g_thread_self () != main_thread || okay_in_main);

  if (!dbus_thread)
    dbus_thread = g_thread_self ();
  g_assert (g_thread_self () == dbus_thread);

  if (g_str_equal (signal_name, "TestSignal"))
    {
      GVariant *expected;

      expected = g_variant_parse (NULL, "(1, 2, 3)", NULL, NULL, NULL);
      g_assert (g_variant_equal (parameters, expected));
      g_variant_unref (expected);

      signal_was_received = TRUE;
    }
}

static void
test_creation_error (void)
{
  /* Sync with 'error' */
  if (g_test_trap_fork (0, 0))
    {
      GError *error = NULL;
      GVariant *reply;

      g_setenv ("DBUS_SESSION_BUS_ADDRESS", "some nonsense", 1);

      reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                                "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                                g_variant_new ("()"), G_VARIANT_TYPE ("(as)"), &error);

      g_assert (reply == NULL);
      g_assert (error != NULL);
      g_assert (strstr (error->message, "some nonsense"));
      exit (0);
    }

  g_test_trap_assert_passed ();

  /* Sync without 'error' */
  if (g_test_trap_fork (0, 0))
    {
      GVariant *reply;

      g_setenv ("DBUS_SESSION_BUS_ADDRESS", "some nonsense", 1);

      reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                                "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                                g_variant_new ("()"), G_VARIANT_TYPE ("(as)"), NULL);

      g_assert (reply == NULL);
      exit (0);
    }

  g_test_trap_assert_passed ();

  /* Async */
  if (g_test_trap_fork (0, 0))
    {
      DConfEngineCallHandle *handle;
      GError *error = NULL;
      gboolean success;

      g_setenv ("DBUS_SESSION_BUS_ADDRESS", "some nonsense", 1);

      handle = g_malloc (1);

      g_mutex_lock (&async_call_queue_lock);
      g_queue_push_tail (&async_call_error_queue, handle);
      g_mutex_unlock (&async_call_queue_lock);

      success = dconf_engine_dbus_call_async_func (G_BUS_TYPE_SESSION,
                                                   "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                                   g_variant_new ("()"), handle, &error);

      /* This could either fail immediately or asynchronously, depending
       * on how the backend is setup.
       */
      if (success)
        {
          g_assert_no_error (error);

          g_mutex_lock (&async_call_queue_lock);
          while (!g_queue_is_empty (&async_call_error_queue))
            g_cond_wait (&async_call_queue_cond, &async_call_queue_lock);
          g_mutex_unlock (&async_call_queue_lock);
        }
      else
        g_assert (error != NULL);

      exit (0);
    }

  g_test_trap_assert_passed ();
}

static void
test_sync_call_success (void)
{
  GError *error = NULL;
  gchar *session_id;
  gchar *system_id;
  GVariant *reply;

  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "ListNames",
                                            g_variant_new ("()"), G_VARIANT_TYPE ("(as)"), &error);

  g_assert_no_error (error);
  g_assert (reply != NULL);
  g_assert (g_variant_is_of_type (reply, G_VARIANT_TYPE ("(as)")));
  g_variant_unref (reply);

  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                            g_variant_new ("()"), G_VARIANT_TYPE ("(s)"), &error);

  g_assert_no_error (error);
  g_assert (reply != NULL);
  g_assert (g_variant_is_of_type (reply, G_VARIANT_TYPE ("(s)")));
  g_variant_get (reply, "(s)", &session_id);
  g_variant_unref (reply);

  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SYSTEM,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                            g_variant_new ("()"), G_VARIANT_TYPE ("(s)"), &error);

  g_assert_no_error (error);
  g_assert (reply != NULL);
  g_assert (g_variant_is_of_type (reply, G_VARIANT_TYPE ("(s)")));
  g_variant_get (reply, "(s)", &system_id);
  g_variant_unref (reply);

  /* Make sure we actually saw two separate buses */
  g_assert_cmpstr (session_id, !=, system_id);
  g_free (session_id);
  g_free (system_id);
}

static void
test_sync_call_error (void)
{
  GError *error = NULL;
  GVariant *reply;

  /* Test receiving errors from the other side */
  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                            g_variant_new ("(u)", 1), G_VARIANT_TYPE_UNIT, &error);
  g_assert (reply == NULL);
  g_assert (error != NULL);
  g_assert (strstr (error->message, "org.freedesktop.DBus.Error.InvalidArgs"));
  g_clear_error (&error);

  /* Test reply type errors */
  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                            g_variant_new ("()"), G_VARIANT_TYPE ("(u)"), &error);
  g_assert (reply == NULL);
  g_assert (error != NULL);
  g_assert (strstr (error->message, " type "));
  g_clear_error (&error);
}

static void
test_async_call_success (void)
{
  gint i;

  for (i = 0; i < 1000; i++)
    {
      DConfEngineCallHandle *handle;
      GError *error = NULL;
      gboolean success;

      handle = g_malloc (1);
      g_mutex_lock (&async_call_queue_lock);
      g_queue_push_tail (&async_call_success_queue, handle);
      g_mutex_unlock (&async_call_queue_lock);

      success = dconf_engine_dbus_call_async_func (G_BUS_TYPE_SESSION,
                                                   "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                                   g_variant_new ("()"), handle, &error);
      g_assert_no_error (error);
      g_assert (success);
    }

  g_mutex_lock (&async_call_queue_lock);
  while (!g_queue_is_empty (&async_call_success_queue))
    g_cond_wait (&async_call_queue_cond, &async_call_queue_lock);
  g_mutex_unlock (&async_call_queue_lock);
}

static void
test_async_call_error (void)
{
  DConfEngineCallHandle *handle;
  GError *error = NULL;
  gboolean success;

  handle = g_malloc (1);

  g_mutex_lock (&async_call_queue_lock);
  g_queue_push_tail (&async_call_error_queue, handle);
  g_mutex_unlock (&async_call_queue_lock);

  success = dconf_engine_dbus_call_async_func (G_BUS_TYPE_SESSION,
                                               "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                               g_variant_new ("(u)", 4), handle, &error);
  g_assert_no_error (error);
  g_assert (success);

  g_mutex_lock (&async_call_queue_lock);
  while (!g_queue_is_empty (&async_call_error_queue))
    g_cond_wait (&async_call_queue_cond, &async_call_queue_lock);
  g_mutex_unlock (&async_call_queue_lock);
}

static void
test_sync_during_async (void)
{
  DConfEngineCallHandle *handle;
  GError *error = NULL;
  gboolean success;
  GVariant *reply;

  handle = g_malloc (1);
  g_mutex_lock (&async_call_queue_lock);
  g_queue_push_tail (&async_call_success_queue, handle);
  g_mutex_unlock (&async_call_queue_lock);

  success = dconf_engine_dbus_call_async_func (G_BUS_TYPE_SESSION,
                                               "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                               g_variant_new ("()"), handle, &error);
  g_assert_no_error (error);
  g_assert (success);

  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "ListNames",
                                            g_variant_new ("()"), G_VARIANT_TYPE ("(as)"), &error);
  g_assert_no_error (error);
  g_assert (reply != NULL);
  g_variant_unref (reply);

  g_mutex_lock (&async_call_queue_lock);
  while (!g_queue_is_empty (&async_call_success_queue))
    g_cond_wait (&async_call_queue_cond, &async_call_queue_lock);
  g_mutex_unlock (&async_call_queue_lock);
}

static void
test_signal_receipt (void)
{
  GError *error = NULL;
  GVariant *reply;
  gint i;

  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "AddMatch",
                                            g_variant_new ("(s)", "type='signal',interface='ca.desrt.dconf.Writer'"),
                                            G_VARIANT_TYPE_UNIT, &error);
  g_assert_no_error (error);
  g_assert (reply != NULL);
  g_variant_unref (reply);

  system ("gdbus emit --session "
          "--object-path /ca/desrt/dconf/Writer/testcase "
          "--signal ca.desrt.dconf.Writer.TestSignal "
          "1 2 3");

  /* total time: 30 seconds */
  for (i = 0; i < 300; i++)
    {
      if (signal_was_received)
        return;

      g_usleep (100 * G_TIME_SPAN_MILLISECOND);
    }

  g_assert_not_reached ();
}

int
main (int argc, char **argv)
{
  g_test_init (&argc, &argv, NULL);

  /* XXX should not need to do this here! */
  g_type_init ();

  main_thread = g_thread_self ();

  /* test_creation_error absolutely must come first */
  g_test_add_func (DBUS_BACKEND "/creation/error", test_creation_error);
  g_test_add_func (DBUS_BACKEND "/sync-call/success", test_sync_call_success);
  g_test_add_func (DBUS_BACKEND "/sync-call/error", test_sync_call_error);
  g_test_add_func (DBUS_BACKEND "/async-call/success", test_async_call_success);
  g_test_add_func (DBUS_BACKEND "/async-call/error", test_async_call_error);
  g_test_add_func (DBUS_BACKEND "/sync-during-async", test_sync_during_async);
  g_test_add_func (DBUS_BACKEND "/signal-receipt", test_signal_receipt);

  return g_test_run ();
}
