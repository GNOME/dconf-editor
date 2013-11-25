#define GLIB_VERSION_MIN_REQUIRED GLIB_VERSION_2_36 /* Suppress deprecation warnings */

#include <string.h>
#include <glib.h>
#include <stdlib.h>

/* Test the DBus communicaton code.
 */

#include "../engine/dconf-engine.h"

static gboolean okay_in_main;
static GThread *main_thread;
static GThread *dbus_thread;
static GQueue   async_call_success_queue;
static GQueue   async_call_error_queue;
static GMutex   async_call_queue_lock;
static gboolean signal_was_received;

static void
wait_for_queue_to_empty (GQueue *queue)
{
  okay_in_main = TRUE;

  while (TRUE)
    {
      gboolean is_empty;

      g_mutex_lock (&async_call_queue_lock);
      is_empty = g_queue_is_empty (queue);
      g_mutex_unlock (&async_call_queue_lock);

      if (is_empty)
        return;

      g_main_context_iteration (NULL, TRUE);
    }

  okay_in_main = FALSE;
}

static gboolean
just_wake (gpointer user_data)
{
  return G_SOURCE_REMOVE;
}

static void
signal_if_queue_is_empty (GQueue *queue)
{
  gboolean is_empty;

  g_mutex_lock (&async_call_queue_lock);
  is_empty = g_queue_is_empty (queue);
  g_mutex_unlock (&async_call_queue_lock);

  if (is_empty)
    g_idle_add (just_wake, NULL);
}

const GVariantType *
dconf_engine_call_handle_get_expected_type (DConfEngineCallHandle *handle)
{
  return (GVariantType *) handle;
}

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
      g_variant_type_free ((GVariantType *) handle);

      signal_if_queue_is_empty (&async_call_success_queue);
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
      g_variant_type_free ((GVariantType *) handle);

      signal_if_queue_is_empty (&async_call_error_queue);
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

      expected = g_variant_parse (NULL, "('1', ['2', '3'])", NULL, NULL, NULL);
      g_assert (g_variant_equal (parameters, expected));
      g_variant_unref (expected);

      signal_was_received = TRUE;
      g_idle_add (just_wake, NULL);
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

      handle = (gpointer) g_variant_type_new ("(s)");
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

          wait_for_queue_to_empty (&async_call_error_queue);
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
                                            g_variant_new ("(s)", ""), G_VARIANT_TYPE_UNIT, &error);
  g_assert (reply == NULL);
  g_assert (error != NULL);
  g_assert (strstr (error->message, "org.freedesktop.DBus.Error.InvalidArgs"));
  g_clear_error (&error);

  /* Test with 'ay' to make sure transmitting that works as well */
  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                            g_variant_new ("(ay)", NULL), G_VARIANT_TYPE_UNIT, &error);
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

  /* Test two oddities:
   *
   *  - first, the dbus-1 backend can't handle return types other than
   *    's' and 'as', so we do a method call that will get something
   *    else in order that we can check that the failure is treated
   *    properly
   *
   *  - next, we want to make sure that the filter function for
   *    gdbus-filter doesn't block incoming method calls
   */
  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "RequestName",
                                            g_variant_new_parsed ("('ca.desrt.dconf.testsuite', uint32 0)"),
                                            G_VARIANT_TYPE ("(u)"), &error);
  if (reply != NULL)
    {
      guint s;

      /* It worked, so we must be on gdbus... */
      g_assert_no_error (error);

      g_variant_get (reply, "(u)", &s);
      g_assert_cmpuint (s, ==, 1);
      g_variant_unref (reply);

      /* Ping ourselves... */
      reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                                "ca.desrt.dconf.testsuite", "/", "org.freedesktop.DBus.Peer",
                                                "Ping", g_variant_new ("()"), G_VARIANT_TYPE_UNIT, &error);
      g_assert (reply != NULL);
      g_assert_no_error (error);
      g_variant_unref (reply);
    }
  else
    {
      /* Else, we're on dbus1...
       *
       * Check that the error was emitted correctly.
       */
      g_assert_cmpstr (error->message, ==, "unable to handle message type '(u)'");
      g_clear_error (&error);
    }
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

      handle = (gpointer) g_variant_type_new ("(s)");
      g_mutex_lock (&async_call_queue_lock);
      g_queue_push_tail (&async_call_success_queue, handle);
      g_mutex_unlock (&async_call_queue_lock);

      success = dconf_engine_dbus_call_async_func (G_BUS_TYPE_SESSION,
                                                   "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                                   g_variant_new ("()"), handle, &error);
      g_assert_no_error (error);
      g_assert (success);
    }

  wait_for_queue_to_empty (&async_call_success_queue);
}

static void
test_async_call_error (void)
{
  DConfEngineCallHandle *handle;
  GError *error = NULL;
  gboolean success;

  handle = (gpointer) g_variant_type_new ("(s)");

  g_mutex_lock (&async_call_queue_lock);
  g_queue_push_tail (&async_call_error_queue, handle);
  g_mutex_unlock (&async_call_queue_lock);

  success = dconf_engine_dbus_call_async_func (G_BUS_TYPE_SESSION,
                                               "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "GetId",
                                               g_variant_new ("(s)", ""), handle, &error);
  g_assert_no_error (error);
  g_assert (success);

  wait_for_queue_to_empty (&async_call_error_queue);
}

static void
test_sync_during_async (void)
{
  DConfEngineCallHandle *handle;
  GError *error = NULL;
  gboolean success;
  GVariant *reply;

  handle = (gpointer) g_variant_type_new ("(s)");
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

  wait_for_queue_to_empty (&async_call_success_queue);
}

static gboolean
did_not_receive_signal (gpointer user_data)
{
  g_assert_not_reached ();
}

static void
test_signal_receipt (void)
{
  GError *error = NULL;
  GVariant *reply;
  gint status;
  guint id;

  reply = dconf_engine_dbus_call_sync_func (G_BUS_TYPE_SESSION,
                                            "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "AddMatch",
                                            g_variant_new ("(s)", "type='signal',interface='ca.desrt.dconf.Writer'"),
                                            G_VARIANT_TYPE_UNIT, &error);
  g_assert_no_error (error);
  g_assert (reply != NULL);
  g_variant_unref (reply);

  status = system ("gdbus emit --session "
                   "--object-path /ca/desrt/dconf/Writer/testcase "
                   "--signal ca.desrt.dconf.Writer.TestSignal "
                   "\"'1'\" \"['2', '3']\"");
  g_assert_cmpint (status, ==, 0);

  id = g_timeout_add (30000, did_not_receive_signal, NULL);
  while (!signal_was_received)
    g_main_context_iteration (NULL, FALSE);
  g_source_remove (id);
}

int
main (int argc, char **argv)
{
  g_test_init (&argc, &argv, NULL);

  main_thread = g_thread_self ();

  dconf_engine_dbus_init_for_testing ();

  /* test_creation_error absolutely must come first */
  if (!g_str_equal (DBUS_BACKEND, "/libdbus-1"))
    g_test_add_func (DBUS_BACKEND "/creation/error", test_creation_error);

  g_test_add_func (DBUS_BACKEND "/sync-call/success", test_sync_call_success);
  g_test_add_func (DBUS_BACKEND "/sync-call/error", test_sync_call_error);
  g_test_add_func (DBUS_BACKEND "/async-call/success", test_async_call_success);
  g_test_add_func (DBUS_BACKEND "/async-call/error", test_async_call_error);
  g_test_add_func (DBUS_BACKEND "/sync-call/during-async", test_sync_during_async);
  g_test_add_func (DBUS_BACKEND "/signal/receipt", test_signal_receipt);

  return g_test_run ();
}
