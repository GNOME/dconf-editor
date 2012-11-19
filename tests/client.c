#define _BSD_SOURCE
#include "../client/dconf-client.h"
#include "../engine/dconf-engine.h"
#include "dconf-mock.h"
#include <string.h>
#include <stdlib.h>

static GThread *main_thread;

static void
test_lifecycle (void)
{
  DConfClient *client;
  GWeakRef weak;

  client = dconf_client_new ();
  g_weak_ref_init (&weak, client);
  g_object_unref (client);

  g_assert (g_weak_ref_get (&weak) == NULL);
  g_weak_ref_clear (&weak);
}

static gboolean changed_was_called;

static void
changed (DConfClient         *client,
         const gchar         *prefix,
         const gchar * const *changes,
         const gchar         *tag,
         gpointer             user_data)
{
  g_assert (g_thread_self () == main_thread);

  changed_was_called = TRUE;
}

static void
check_and_free (GVariant *to_check,
                GVariant *expected)
{
  if (expected)
    {
      g_variant_ref_sink (expected);
      g_assert (to_check);

      g_assert (g_variant_equal (to_check, expected));
      g_variant_unref (to_check);
      g_variant_unref (expected);
    }
  else
    g_assert (to_check == NULL);
}

static void
queue_up_100_writes (DConfClient *client)
{
  gint i;

  /* We send 100 writes, letting them pile up.
   * At no time should there be more than 2 writes on the wire.
   */
  for (i = 0; i < 100; i++)
    {
      changed_was_called = FALSE;
      dconf_client_write_fast (client, "/test/value", g_variant_new_int32 (i), NULL);
      g_assert (changed_was_called);

      /* We should always see the most recently written value. */
      check_and_free (dconf_client_read (client, "/test/value"), g_variant_new_int32 (i));
    }

  g_assert_cmpint (g_queue_get_length (&dconf_mock_dbus_outstanding_call_handles), ==, 2);
}

static void
fail_one_call (void)
{
  DConfEngineCallHandle *handle;
  GError *error;

  error = g_error_new_literal (G_FILE_ERROR, G_FILE_ERROR_NOENT, "--expected error from testcase--");
  handle = g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles);
  dconf_engine_call_handle_reply (handle, NULL, error);
  g_error_free (error);
}

static void
log_handler (const gchar    *log_domain,
             GLogLevelFlags  log_level,
             const gchar    *message,
             gpointer        user_data)
{
  if (strstr (message, "--expected error from testcase--"))
    return;

  g_log_default_handler (log_domain, log_level, message, user_data);
}

static gboolean
fatal_log_handler (const gchar    *log_domain,
                   GLogLevelFlags  log_level,
                   const gchar    *message,
                   gpointer        user_data)
{
  if (strstr (message, "--expected error from testcase--"))
    return FALSE;

  return TRUE;
}

static void
test_fast (void)
{
  DConfClient *client;
  gint i;

  g_log_set_default_handler (log_handler, NULL);
  g_test_log_set_fatal_handler (fatal_log_handler, NULL);

  client = dconf_client_new ();
  g_signal_connect (client, "changed", G_CALLBACK (changed), NULL);

  queue_up_100_writes (client);

  /* Start indicating that the writes failed.
   *
   * For the first failures, we should continue to see the most recently
   * written value (99).
   *
   * After we fail that last one, we should see NULL returned.
   *
   * Each time, we should see a change notify.
   */

  for (i = 0; g_queue_get_length (&dconf_mock_dbus_outstanding_call_handles) > 1; i++)
    {
      changed_was_called = FALSE;
      fail_one_call ();
      g_assert (changed_was_called);

      check_and_free (dconf_client_read (client, "/test/value"), g_variant_new_int32 (99));
    }

  /* Because of the pending-merging logic, we should only have had to
   * fail two calls.
   */
  g_assert (i == 2);

  /* Fail the last call. */
  changed_was_called = FALSE;
  fail_one_call ();
  g_assert (changed_was_called);

  /* Should read back now as NULL */
  check_and_free (dconf_client_read (client, "/test/value"), NULL);

  /* Cleanup */
  g_signal_handlers_disconnect_by_func (client, changed, NULL);
  g_object_unref (client);
}

int
main (int argc, char **argv)
{
  setenv ("DCONF_PROFILE", SRCDIR "/profile/will-never-exist", TRUE);

  main_thread = g_thread_self ();

  g_test_init (&argc, &argv, NULL);

  g_test_add_func ("/client/lifecycle", test_lifecycle);
  g_test_add_func ("/client/basic-fast", test_fast);

  return g_test_run ();
}
