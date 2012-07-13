#define _GNU_SOURCE

#include "../engine/dconf-engine.h"
#include "../engine/dconf-engine-profile.h"
#include "dconf-mock.h"
#include <stdlib.h>
#include <stdio.h>
#include <dlfcn.h>

/* Interpose to catch fopen("/etc/dconf/profile/user") */
static const gchar *filename_to_replace;
static const gchar *filename_to_replace_it_with;

FILE *
fopen (const char *filename,
       const char *mode)
{
  static FILE * (*real_fopen) (const char *, const char *);

  if (!real_fopen)
    real_fopen = dlsym (RTLD_NEXT, "fopen");

  if (filename_to_replace && g_str_equal (filename, filename_to_replace))
    {
      /* Crash if this file was unexpectedly opened */
      g_assert (filename_to_replace_it_with != NULL);
      filename = filename_to_replace_it_with;
    }

  return (* real_fopen) (filename, mode);
}

static GThread *main_thread;

void
dconf_engine_change_notify (DConfEngine         *engine,
                            const gchar         *prefix,
                            const gchar * const *changes,
                            const gchar         *tag,
                            gpointer             user_data)
{
  /* ignore */
}

static void
verify_and_free (DConfEngineSource  **sources,
                 gint                 n_sources,
                 const gchar * const *expected_names,
                 gint                 n_expected)
{
  gint i;

  g_assert_cmpint (n_sources, ==, n_expected);

  g_assert ((sources == NULL) == (n_sources == 0));

  for (i = 0; i < n_sources; i++)
    {
      g_assert_cmpstr (sources[i]->name, ==, expected_names[i]);
      dconf_engine_source_free (sources[i]);
    }

  g_free (sources);
}

static void
test_five_times (const gchar *filename,
                 gint         n_expected,
                 ...)
{
  const gchar **expected_names;
  DConfEngineSource **sources;
  gint n_sources;
  va_list ap;
  gint i;

  expected_names = g_new (const gchar *, n_expected);
  va_start (ap, n_expected);
  for (i = 0; i < n_expected; i++)
    expected_names[i] = va_arg (ap, const gchar *);
  va_end (ap);

  /* first try by supplying the profile filename via the API */
  g_assert (g_getenv ("DCONF_PROFILE") == NULL);
  g_assert (filename_to_replace == NULL);
  sources = dconf_engine_profile_open (filename, &n_sources);
  verify_and_free (sources, n_sources, expected_names, n_expected);

  /* next try supplying it via the environment */
  g_setenv ("DCONF_PROFILE", filename, TRUE);
  g_assert (filename_to_replace == NULL);
  sources = dconf_engine_profile_open (NULL, &n_sources);
  verify_and_free (sources, n_sources, expected_names, n_expected);
  g_unsetenv ("DCONF_PROFILE");

  /* next try supplying a profile name via API and intercepting fopen */
  filename_to_replace = "/etc/dconf/profile/myprofile";
  filename_to_replace_it_with = filename;
  g_assert (g_getenv ("DCONF_PROFILE") == NULL);
  sources = dconf_engine_profile_open ("myprofile", &n_sources);
  verify_and_free (sources, n_sources, expected_names, n_expected);
  filename_to_replace = NULL;

  /* next try the same, via the environment */
  g_setenv ("DCONF_PROFILE", "myprofile", TRUE);
  filename_to_replace = "/etc/dconf/profile/myprofile";
  filename_to_replace_it_with = filename;
  sources = dconf_engine_profile_open (NULL, &n_sources);
  verify_and_free (sources, n_sources, expected_names, n_expected);
  g_unsetenv ("DCONF_PROFILE");
  filename_to_replace = NULL;

  /* next try to have dconf pick it up as the default user profile */
  filename_to_replace = "/etc/dconf/profile/user";
  filename_to_replace_it_with = filename;
  g_assert (g_getenv ("DCONF_PROFILE") == NULL);
  sources = dconf_engine_profile_open (NULL, &n_sources);
  verify_and_free (sources, n_sources, expected_names, n_expected);
  filename_to_replace = NULL;

  filename_to_replace_it_with = NULL;
  g_free (expected_names);
}

static void
test_profile_parser (void)
{
  DConfEngineSource **sources;
  gint n_sources;

  if (g_test_trap_fork (0, G_TEST_TRAP_SILENCE_STDERR))
    {
      g_log_set_always_fatal (G_LOG_LEVEL_ERROR);

      sources = dconf_engine_profile_open (SRCDIR "/profile/this-file-does-not-exist", &n_sources);
      g_assert_cmpint (n_sources, ==, 0);
      g_assert (sources == NULL);
      exit (0);
    }
  g_test_trap_assert_passed ();
  g_test_trap_assert_stderr ("*WARNING*: unable to open named profile*");

  if (g_test_trap_fork (0, G_TEST_TRAP_SILENCE_STDERR))
    {
      g_log_set_always_fatal (G_LOG_LEVEL_ERROR);

      sources = dconf_engine_profile_open (SRCDIR "/profile/broken-profile", &n_sources);
      g_assert_cmpint (n_sources, ==, 0);
      g_assert (sources == NULL);
      exit (0);
    }
  g_test_trap_assert_passed ();
  g_test_trap_assert_stderr ("*WARNING*: unknown dconf database*unknown dconf database*");

  test_five_times (SRCDIR "/profile/empty-profile", 0);
  test_five_times (SRCDIR "/profile/test-profile", 1, "test");
  test_five_times (SRCDIR "/profile/colourful", 4,
                   "user",
                   "other",
                   "verylongnameverylongnameverylongnameverylongnameverylongnameverylongnameverylongnameverylongnameverylongnameverylongnameverylongnameverylongname",
                   "nonewline");
  test_five_times (SRCDIR "/profile/dos", 2, "user", "site");
  test_five_times (SRCDIR "/profile/no-newline-longline", 0);
  test_five_times (SRCDIR "/profile/many-sources", 10,
                   "user", "local", "room", "floor", "building",
                   "site", "region", "division", "country", "global");

  /* finally, test that we get the default profile if the user profile
   * file cannot be located and we do not specify another profile.
   */
  filename_to_replace = "/etc/dconf/profile/user";
  filename_to_replace_it_with = SRCDIR "/profile/this-file-does-not-exist";
  g_assert (g_getenv ("DCONF_PROFILE") == NULL);
  sources = dconf_engine_profile_open (NULL, &n_sources);
  filename_to_replace = NULL;
  g_assert_cmpint (n_sources, ==, 1);
  g_assert_cmpstr (sources[0]->name, ==, "user");
  dconf_engine_source_free (sources[0]);
  g_free (sources);

  dconf_mock_shm_reset ();
}

static gpointer
test_signal_threadsafety_worker (gpointer user_data)
{
  gint *finished = user_data;
  gint i;

  for (i = 0; i < 20000; i++)
    {
      DConfEngine *engine;

      engine = dconf_engine_new (NULL, NULL);
      dconf_engine_unref (engine);
    }

  g_atomic_int_inc (finished);

  return NULL;
}

static void
test_signal_threadsafety (void)
{
#define N_WORKERS 4
  GVariant *parameters;
  gint finished = 0;
  gint i;

  parameters = g_variant_new_parsed ("('/test/key', [''], 'tag')");
  g_variant_ref_sink (parameters);

  for (i = 0; i < N_WORKERS; i++)
    g_thread_unref (g_thread_new ("testcase worker", test_signal_threadsafety_worker, &finished));

  while (g_atomic_int_get (&finished) < N_WORKERS)
    dconf_engine_handle_dbus_signal (G_BUS_TYPE_SESSION,
                                     ":1.2.3",
                                     "/ca/desrt/dconf/Writer/user",
                                     "Notify", parameters);
  g_variant_unref (parameters);

  dconf_mock_shm_reset ();
}

static void
test_user_source (void)
{
  DConfEngineSource *source;
  GvdbTable *table;
  GvdbTable *locks;
  gboolean reopened;

  /* Create the source from a clean slate */
  source = dconf_engine_source_new ("user-db:user");
  g_assert (source != NULL);
  g_assert (source->values == NULL);
  g_assert (source->locks == NULL);

  /* Refresh it the first time.
   * This should cause it to open the shm.
   * FALSE should be returned because there is no database file.
   */
  reopened = dconf_engine_source_refresh (source);
  g_assert (!reopened);
  dconf_mock_shm_assert_log ("open user;");

  /* Try to refresh it.  There must be no IO at this point. */
  reopened = dconf_engine_source_refresh (source);
  g_assert (!reopened);
  dconf_mock_shm_assert_log ("");

  /* Add a real database. */
  table = dconf_mock_gvdb_table_new ();
  dconf_mock_gvdb_table_insert (table, "/values/int32", g_variant_new_int32 (123456), NULL);
  dconf_mock_gvdb_install ("/HOME/.config/dconf/user", table);

  /* Try to refresh it again.
   * Because we didn't flag the change there must still be no IO.
   */
  reopened = dconf_engine_source_refresh (source);
  g_assert (!reopened);
  g_assert (source->values == NULL);
  g_assert (source->locks == NULL);
  dconf_mock_shm_assert_log ("");

  /* Now flag it and reopen. */
  dconf_mock_shm_flag ("user");
  reopened = dconf_engine_source_refresh (source);
  g_assert (reopened);
  g_assert (source->values != NULL);
  g_assert (source->locks == NULL);
  g_assert (gvdb_table_has_value (source->values, "/values/int32"));
  dconf_mock_shm_assert_log ("close;open user;");

  /* Do it again -- should get the same result, after some IO */
  dconf_mock_shm_flag ("user");
  reopened = dconf_engine_source_refresh (source);
  g_assert (reopened);
  g_assert (source->values != NULL);
  g_assert (source->locks == NULL);
  dconf_mock_shm_assert_log ("close;open user;");

  /* "Delete" the gvdb and make sure dconf notices after a flag */
  dconf_mock_gvdb_install ("/HOME/.config/dconf/user", NULL);
  dconf_mock_shm_flag ("user");
  reopened = dconf_engine_source_refresh (source);
  g_assert (reopened);
  g_assert (source->values == NULL);
  g_assert (source->locks == NULL);
  dconf_mock_shm_assert_log ("close;open user;");

  /* Add a gvdb with a lock */
  table = dconf_mock_gvdb_table_new ();
  locks = dconf_mock_gvdb_table_new ();
  dconf_mock_gvdb_table_insert (table, "/values/int32", g_variant_new_int32 (123456), NULL);
  dconf_mock_gvdb_table_insert (locks, "/values/int32", g_variant_new_boolean (TRUE), NULL);
  dconf_mock_gvdb_table_insert (table, ".locks", NULL, locks);
  dconf_mock_gvdb_install ("/HOME/.config/dconf/user", table);

  /* Reopen and check if we have the lock */
  dconf_mock_shm_flag ("user");
  reopened = dconf_engine_source_refresh (source);
  g_assert (reopened);
  g_assert (source->values != NULL);
  g_assert (source->locks != NULL);
  g_assert (gvdb_table_has_value (source->values, "/values/int32"));
  g_assert (gvdb_table_has_value (source->locks, "/values/int32"));
  dconf_mock_shm_assert_log ("close;open user;");

  /* Reopen one last time */
  dconf_mock_shm_flag ("user");
  reopened = dconf_engine_source_refresh (source);
  g_assert (reopened);
  g_assert (source->values != NULL);
  g_assert (source->locks != NULL);
  dconf_mock_shm_assert_log ("close;open user;");

  dconf_engine_source_free (source);
  dconf_mock_shm_assert_log ("close;");

  dconf_mock_gvdb_install ("/HOME/.config/dconf/user", NULL);
  dconf_mock_shm_reset ();
}

static void
test_system_source (void)
{
  DConfEngineSource *source;
  GvdbTable *table;
  gboolean reopened;

  source = dconf_engine_source_new ("system-db:site");
  g_assert (source != NULL);

  /* Check to see that we get the warning about the missing file. */
  if (g_test_trap_fork (0, G_TEST_TRAP_SILENCE_STDERR))
    {
      g_log_set_always_fatal (G_LOG_LEVEL_ERROR);

      /* Failing to open should return FALSE from refresh */
      reopened = dconf_engine_source_refresh (source);
      g_assert (!reopened);
      g_assert (source->values == NULL);

      /* Attempt the reopen to make sure we don't get two warnings.
       * We should see FALSE again since we go from NULL to NULL.
       */
      reopened = dconf_engine_source_refresh (source);
      g_assert (!reopened);

      /* Create the file after the fact and make sure it opens properly */
      table = dconf_mock_gvdb_table_new ();
      dconf_mock_gvdb_install ("/etc/dconf/db/site", table);

      reopened = dconf_engine_source_refresh (source);
      g_assert (reopened);
      g_assert (source->values != NULL);

      dconf_engine_source_free (source);

      exit (0);
    }
  g_test_trap_assert_passed ();
  /* Check that we only saw the warning, but only one time. */
  g_test_trap_assert_stderr ("*this gvdb does not exist; expect degraded performance*");
  g_test_trap_assert_stderr_unmatched ("*degraded*degraded*");

  /* Create the file before the first refresh attempt */
  table = dconf_mock_gvdb_table_new ();
  dconf_mock_gvdb_install ("/etc/dconf/db/site", table);

  /* See that we get the database. */
  reopened = dconf_engine_source_refresh (source);
  g_assert (reopened);
  g_assert (source->values != NULL);

  /* Do a refresh, make sure there is no change. */
  reopened = dconf_engine_source_refresh (source);
  g_assert (!reopened);

  dconf_engine_source_free (source);
}

int
main (int argc, char **argv)
{
  g_setenv ("XDG_CONFIG_HOME", "/HOME/.config", TRUE);
  g_unsetenv ("DCONF_PROFILE");

  main_thread = g_thread_self ();

  g_test_init (&argc, &argv, NULL);

  g_test_add_func ("/engine/profile-parser", test_profile_parser);
  g_test_add_func ("/engine/signal-threadsafety", test_signal_threadsafety);
  g_test_add_func ("/engine/sources/user", test_user_source);
  g_test_add_func ("/engine/sources/system", test_system_source);

  return g_test_run ();
}
