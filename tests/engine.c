#define _GNU_SOURCE

#include "../engine/dconf-engine.h"
#include "../engine/dconf-engine-profile.h"
#include "dconf-mock.h"

#include <glib/gstdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <dlfcn.h>
#include <math.h>

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
static GString *change_log;

void
dconf_engine_change_notify (DConfEngine         *engine,
                            const gchar         *prefix,
                            const gchar * const *changes,
                            const gchar         *tag,
                            gpointer             origin_tag,
                            gpointer             user_data)
{
  if (change_log)
    g_string_append_printf (change_log, "%s:%d:%s:%s;",
                            prefix, g_strv_length ((gchar **) changes), changes[0],
                            tag ? tag : "nil");
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

  if (g_test_trap_fork (0, G_TEST_TRAP_SILENCE_STDERR))
    {
      g_log_set_always_fatal (G_LOG_LEVEL_ERROR);

      sources = dconf_engine_profile_open (SRCDIR "/profile/gdm", &n_sources);
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
  GvdbTable *first_table;
  GvdbTable *next_table;
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
      first_table = dconf_mock_gvdb_table_new ();
      dconf_mock_gvdb_install ("/etc/dconf/db/site", first_table);

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
  first_table = dconf_mock_gvdb_table_new ();
  dconf_mock_gvdb_install ("/etc/dconf/db/site", first_table);
  /* Hang on to a copy for ourselves for below... */
  dconf_mock_gvdb_table_ref (first_table);

  /* See that we get the database. */
  reopened = dconf_engine_source_refresh (source);
  g_assert (reopened);
  g_assert (source->values == first_table);

  /* Do a refresh, make sure there is no change. */
  reopened = dconf_engine_source_refresh (source);
  g_assert (!reopened);
  g_assert (source->values == first_table);

  /* Replace the table on "disk" but don't invalidate the old one */
  next_table = dconf_mock_gvdb_table_new ();
  dconf_mock_gvdb_install ("/etc/dconf/db/site", next_table);

  /* Make sure the old table remains open (ie: no IO performed) */
  reopened = dconf_engine_source_refresh (source);
  g_assert (!reopened);
  g_assert (source->values == first_table);

  /* Now mark the first table invalid and reopen */
  dconf_mock_gvdb_table_invalidate (first_table);
  gvdb_table_free (first_table);
  reopened = dconf_engine_source_refresh (source);
  g_assert (reopened);
  g_assert (source->values == next_table);

  /* Remove the file entirely and do the same thing */
  dconf_mock_gvdb_install ("/etc/dconf/db/site", NULL);
  reopened = dconf_engine_source_refresh (source);
  g_assert (!reopened);

  dconf_engine_source_free (source);
}

static void
invalidate_state (guint     n_sources,
                  guint     source_types,
                  gpointer *state)
{
  gint i;

  for (i = 0; i < n_sources; i++)
    if (source_types & (1u << i))
      {
        if (state[i])
          {
            dconf_mock_gvdb_table_invalidate (state[i]);
            gvdb_table_free (state[i]);
          }
      }
    else
      {
        dconf_mock_shm_flag (state[i]);
        g_free (state[i]);
      }
}

static void
setup_state (guint     n_sources,
             guint     source_types,
             guint     database_state,
             gpointer *state)
{
  gint i;

  for (i = 0; i < n_sources; i++)
    {
      guint contents = database_state % 7;
      GvdbTable *table = NULL;
      gchar *filename;

      if (contents)
        {
          table = dconf_mock_gvdb_table_new ();

          /* Even numbers get the value setup */
          if ((contents & 1) == 0)
            dconf_mock_gvdb_table_insert (table, "/value", g_variant_new_uint32 (i), NULL);

          /* Numbers above 2 get the locks table */
          if (contents > 2)
            {
              GvdbTable *locks;

              locks = dconf_mock_gvdb_table_new ();

              /* Numbers above 4 get the lock set */
              if (contents > 4)
                dconf_mock_gvdb_table_insert (locks, "/value", g_variant_new_boolean (TRUE), NULL);

              dconf_mock_gvdb_table_insert (table, ".locks", NULL, locks);
            }
        }

      if (source_types & (1u << i))
        {
          if (state)
            {
              if (table)
                state[i] = dconf_mock_gvdb_table_ref (table);
              else
                state[i] = NULL;
            }

          filename = g_strdup_printf ("/etc/dconf/db/db%d", i);
        }
      else
        {
          if (state)
            state[i] = g_strdup_printf ("db%d", i);

          filename = g_strdup_printf ("/HOME/.config/dconf/db%d", i);
        }

      dconf_mock_gvdb_install (filename, table);
      g_free (filename);

      database_state /= 7;
    }
}

static void
create_profile (const gchar *filename,
                guint        n_sources,
                guint        source_types)
{
  GError *error = NULL;
  GString *profile;
  gint i;

  profile = g_string_new (NULL);
  for (i = 0; i < n_sources; i++)
    if (source_types & (1u << i))
      g_string_append_printf (profile, "system-db:db%d\n", i);
    else
      g_string_append_printf (profile, "user-db:db%d\n", i);
  g_file_set_contents (filename, profile->str, profile->len, &error);
  g_assert_no_error (error);
  g_string_free (profile, TRUE);
}

static void
check_read (DConfEngine *engine,
            guint        n_sources,
            guint        source_types,
            guint        database_state)
{
  gboolean any_values = FALSE;
  gboolean any_locks = FALSE;
  gint expected = -1;
  gboolean writable;
  GVariant *value;
  gchar **list;
  guint i;

  /* The value we expect to read is number of the first source that has
   * the value set (ie: odd digit in database_state) up to the lowest
   * level lock.
   *
   * We go over each database.  If 'expected' has not yet been set and
   * we find that we should have a value in this database, we set it.
   * If we find that we should have a lock in this database, we unset
   * any previous values (since they should not have been written).
   *
   * We initially code this loop in a different way than the one in
   * dconf itself is currently implemented...
   *
   * We also take note of if we saw any locks and cross-check that with
   * dconf_engine_is_writable().  We check if we saw and values at all
   * and cross-check that with dconf_engine_list() (which ignores
   * locks).
   */
  for (i = 0; i < n_sources; i++)
    {
      guint contents = database_state % 7;

      /* A lock here should prevent higher reads */
      if (contents > 4)
        {
          /* Locks in the first database don't count... */
          if (i != 0)
            any_locks = TRUE;
          expected = -1;
        }

      /* A value here should be read */
      if (contents && !(contents & 1) && expected == -1)
        {
          any_values = TRUE;
          expected = i;
        }

      database_state /= 7;
    }

  value = dconf_engine_read (engine, NULL, "/value");

  if (expected != -1)
    {
      g_assert (g_variant_is_of_type (value, G_VARIANT_TYPE_UINT32));
      g_assert_cmpint (g_variant_get_uint32 (value), ==, expected);
      g_variant_unref (value);
    }
  else
    g_assert (value == NULL);

  /* We are writable if the first database is a user database and we
   * didn't encounter any locks...
   */
  writable = dconf_engine_is_writable (engine, "/value");
  g_assert_cmpint (writable, ==, n_sources && !(source_types & 1) && !any_locks);

  list = dconf_engine_list (engine, "/", NULL);
  if (any_values)
    {
      g_assert_cmpstr (list[0], ==, "value");
      g_assert (list[1] == NULL);
    }
  else
    g_assert (list[0] == NULL);
  g_strfreev (list);
}

static void
test_read (void)
{
#define MAX_N_SOURCES 3
  gpointer state[MAX_N_SOURCES];
  gchar *profile_filename;
  GError *error = NULL;
  DConfEngine *engine;
  guint i, j, k;
  guint n;

  /* Hack to silence warning */
  if (!g_test_trap_fork (0, G_TEST_TRAP_SILENCE_STDERR))
    {
      g_test_trap_assert_passed ();
      g_test_trap_assert_stderr ("*this gvdb does not exist; expect degraded performance*");
      return;
    }
  g_log_set_always_fatal (G_LOG_LEVEL_ERROR);

  /* Our test strategy is as follows:
   *
   * We only test a single key name.  It is assumed that gvdb is working
   * properly already so we are only interested in interactions between
   * multiple databases for a given key name.
   *
   * The outermost loop is over 'n'.  This is how many sources are in
   * our test.  We test 0 to 3 (which should be enough to cover all
   * 'interesting' possibilities).  4 takes too long to run (2*7*7 ~=
   * 100 times as long as 3).
   *
   * The next loop is over 'i'.  This goes from 0 to 2^n - 1, with each
   * bit deciding the type of source of the i-th element
   *
   *   0: user
   *
   *   1: system
   *
   * The next loop is over 'j'.  This goes from 0 to 7^n - 1, with each
   * base-7 digit deciding the state of the database file associated
   * with the i-th source:
   *
   *   j      file    has value   has ".locks"   has lock
   *  ----------------------------------------------------
   *   0      0       -           -              -
   *   1      1       0           0              -
   *   2      1       1           0              -
   *   3      1       0           1              0
   *   4      1       1           1              0
   *   5      1       0           1              1
   *   6      1       1           1              1
   *
   * Where 'file' is if the database file exists, 'has value' is if a
   * value exists at '/value' within the file, 'has ".locks"' is if
   * there is a ".locks" subtable and 'has lock' is if there is a lock
   * for '/value' within that table.
   *
   * Finally, we loop over 'k' as a state to transition to ('k' works
   * the same way as 'j').
   *
   * Once we know 'n' and 'i', we can write a profile file.
   *
   * Once we know 'j' we can setup the initial state, create the engine
   * and check that we got the expected value.  Then we transition to
   * state 'k' and make sure everything still works as expected.
   *
   * Since we want to test all j->k transitions, we do the initial setup
   * of the engine (according to j) inside of the 'k' loop, since we
   * need to test all possible transitions from 'j'.
   */

  /* We need a place to put the profile files we use for this test */
  close (g_file_open_tmp ("dconf-testcase.XXXXXX", &profile_filename, &error));
  g_assert_no_error (error);

  g_setenv ("DCONF_PROFILE", profile_filename, TRUE);

  for (n = 0; n < MAX_N_SOURCES; n++)
    for (i = 0; i < pow (2, n); i++)
      {
        gint n_possible_states = pow (7, n);

        /* Step 1: write out the profile file */
        create_profile (profile_filename, n, i);

        for (j = 0; j < n_possible_states; j++)
          for (k = 0; k < n_possible_states; k++)
            {
              guint64 old_state, new_state;

              /* Step 2: setup the state */
              setup_state (n, i, j, (j != k) ? state : NULL);

              /* Step 3: create the engine */
              engine = dconf_engine_new (NULL, NULL);

              /* Step 4: read, and check result */
              check_read (engine, n, i, j);
              old_state = dconf_engine_get_state (engine);

              /* Step 5: change to the new state */
              if (j != k)
                {
                  setup_state (n, i, k, NULL);
                  invalidate_state (n, i, state);
                }

              /* Step 6: read, and check result */
              check_read (engine, n, i, k);
              new_state = dconf_engine_get_state (engine);

              g_assert ((j == k) == (new_state == old_state));

              /* Clean up */
              setup_state (n, i, 0, NULL);
              dconf_engine_unref (engine);
            }
      }

  /* Clean up the tempfile we were using... */
  g_unsetenv ("DCONF_PROFILE");
  g_unlink (profile_filename);
  g_free (profile_filename);
  exit (0);
}

static void
test_watch_fast (void)
{
  DConfEngine *engine;
  GvdbTable *table;
  GVariant *triv;
  guint64 a, b;

  change_log = g_string_new (NULL);

  table = dconf_mock_gvdb_table_new ();
  dconf_mock_gvdb_install ("/HOME/.config/dconf/user", table);
  table = dconf_mock_gvdb_table_new ();
  dconf_mock_gvdb_install ("/etc/dconf/db/site", table);

  triv = g_variant_ref_sink (g_variant_new ("()"));

  g_setenv ("DCONF_PROFILE", SRCDIR "/profile/dos", TRUE);
  engine = dconf_engine_new (NULL, NULL);
  g_unsetenv ("DCONF_PROFILE");

  /* Check that establishing a watch works properly in the normal case.
   */
  a = dconf_engine_get_state (engine);
  dconf_engine_watch_fast (engine, "/a/b/c");
  /* watches do not count as outstanding changes */
  g_assert (!dconf_engine_has_outstanding (engine));
  dconf_engine_sync (engine);
  b = dconf_engine_get_state (engine);
  g_assert_cmpuint (a, ==, b);
  /* both AddMatch results come back before shm is flagged */
  dconf_engine_call_handle_reply (g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles), triv, NULL);
  dconf_engine_call_handle_reply (g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles), triv, NULL);
  g_assert (g_queue_is_empty (&dconf_mock_dbus_outstanding_call_handles));
  dconf_mock_shm_flag ("user");
  b = dconf_engine_get_state (engine);
  g_assert_cmpuint (a, !=, b);
  g_assert_cmpstr (change_log->str, ==, "");
  dconf_engine_unwatch_fast (engine, "/a/b/c");
  dconf_engine_call_handle_reply (g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles), triv, NULL);
  dconf_engine_call_handle_reply (g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles), triv, NULL);
  g_assert (g_queue_is_empty (&dconf_mock_dbus_outstanding_call_handles));

  /* Establish a watch and fail the race. */
  a = dconf_engine_get_state (engine);
  dconf_engine_watch_fast (engine, "/a/b/c");
  g_assert (!dconf_engine_has_outstanding (engine));
  dconf_engine_sync (engine);
  b = dconf_engine_get_state (engine);
  g_assert_cmpuint (a, ==, b);
  /* one AddMatch result comes back -after- shm is flagged */
  dconf_engine_call_handle_reply (g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles), triv, NULL);
  dconf_mock_shm_flag ("user");
  dconf_engine_call_handle_reply (g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles), triv, NULL);
  g_assert (g_queue_is_empty (&dconf_mock_dbus_outstanding_call_handles));
  b = dconf_engine_get_state (engine);
  g_assert_cmpuint (a, !=, b);
  g_assert_cmpstr (change_log->str, ==, "/:1::nil;");
  dconf_engine_unwatch_fast (engine, "/a/b/c");
  dconf_engine_call_handle_reply (g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles), triv, NULL);
  dconf_engine_call_handle_reply (g_queue_pop_head (&dconf_mock_dbus_outstanding_call_handles), triv, NULL);
  g_assert (g_queue_is_empty (&dconf_mock_dbus_outstanding_call_handles));

  dconf_mock_gvdb_install ("/HOME/.config/dconf/user", NULL);
  dconf_mock_gvdb_install ("/etc/dconf/db/site", NULL);
  dconf_engine_unref (engine);
  g_string_free (change_log, TRUE);
  change_log = NULL;
  g_variant_unref (triv);
}

static const gchar *match_request_type;
static gboolean got_match_request[5];

static GVariant *
handle_match_request (GBusType             bus_type,
                      const gchar         *bus_name,
                      const gchar         *object_path,
                      const gchar         *interface_name,
                      const gchar         *method_name,
                      GVariant            *parameters,
                      const GVariantType  *expected_type,
                      GError             **error)
{
  const gchar *match_rule;

  g_assert_cmpstr (bus_name, ==, "org.freedesktop.DBus");
  /* any object path works... */
  g_assert_cmpstr (bus_name, ==, "org.freedesktop.DBus");
  g_assert_cmpstr (method_name, ==, match_request_type);
  g_assert_cmpstr (g_variant_get_type_string (parameters), ==, "(s)");
  g_variant_get (parameters, "(&s)", &match_rule);
  g_assert (strstr (match_rule, "arg0path='/a/b/c'"));
  g_assert (!got_match_request[bus_type]);
  got_match_request[bus_type] = TRUE;

  return g_variant_new ("()");
}

static void
test_watch_sync (void)
{
  DConfEngine *engine;

  dconf_mock_dbus_sync_call_handler = handle_match_request;

  g_setenv ("DCONF_PROFILE", SRCDIR "/profile/dos", TRUE);
  engine = dconf_engine_new (NULL, NULL);
  g_unsetenv ("DCONF_PROFILE");

  match_request_type = "AddMatch";
  dconf_engine_watch_sync (engine, "/a/b/c");
  g_assert (got_match_request[G_BUS_TYPE_SESSION]);
  g_assert (got_match_request[G_BUS_TYPE_SYSTEM]);
  got_match_request[G_BUS_TYPE_SESSION] = FALSE;
  got_match_request[G_BUS_TYPE_SYSTEM] = FALSE;

  match_request_type = "RemoveMatch";
  dconf_engine_unwatch_sync (engine, "/a/b/c");
  g_assert (got_match_request[G_BUS_TYPE_SESSION]);
  g_assert (got_match_request[G_BUS_TYPE_SYSTEM]);
  got_match_request[G_BUS_TYPE_SESSION] = FALSE;
  got_match_request[G_BUS_TYPE_SYSTEM] = FALSE;

  dconf_engine_unref (engine);

  dconf_mock_dbus_sync_call_handler = NULL;
  match_request_type = NULL;
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
  g_test_add_func ("/engine/read", test_read);
  g_test_add_func ("/engine/watch/fast", test_watch_fast);
  g_test_add_func ("/engine/watch/sync", test_watch_sync);

  return g_test_run ();
}
