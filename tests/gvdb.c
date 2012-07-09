#include <glib.h>
#include "../gvdb/gvdb-reader.h"

static void
test_reader_open_error (void)
{
  GError *error = NULL;
  GvdbTable *table;

  table = gvdb_table_new (SRCDIR "/gvdbs/does_not_exist", TRUE, &error);
  g_assert_error (error, G_FILE_ERROR, G_FILE_ERROR_NOENT);
  g_assert (table == NULL);
  g_clear_error (&error);

  table = gvdb_table_new (SRCDIR "/gvdbs/file_empty", TRUE, &error);
  g_assert_error (error, G_FILE_ERROR, G_FILE_ERROR_INVAL);
  g_assert (table == NULL);
  g_clear_error (&error);

  table = gvdb_table_new (SRCDIR "/gvdbs/invalid_header", TRUE, &error);
  g_assert_error (error, G_FILE_ERROR, G_FILE_ERROR_INVAL);
  g_assert (table == NULL);
  g_clear_error (&error);

  table = gvdb_table_new (SRCDIR "/gvdbs/file_too_small", TRUE, &error);
  g_assert_error (error, G_FILE_ERROR, G_FILE_ERROR_INVAL);
  g_assert (table == NULL);
  g_clear_error (&error);
}

static void
test_reader_empty (void)
{
  const gchar * strings[] = { "", "value", "/value", ".", NULL};
  GError *error = NULL;
  GvdbTable *table;
  gint i;

  table = gvdb_table_new (SRCDIR "/gvdbs/empty_gvdb", TRUE, &error);
  g_assert_no_error (error);
  g_assert (table != NULL);

  table = gvdb_table_ref (table);
  gvdb_table_unref (table);

  g_assert (gvdb_table_is_valid (table));

  for (i = 0; strings[i]; i++)
    {
      const gchar *key = strings[i];
      GvdbTable *sub;
      GVariant *val;
      gboolean has;
      gchar **list;

      sub = gvdb_table_get_table (table, key);
      g_assert (sub == NULL);

      has = gvdb_table_has_value (table, key);
      g_assert (!has);

      val = gvdb_table_get_value (table, key);
      g_assert (val == NULL);

      val = gvdb_table_get_raw_value (table, key);
      g_assert (val == NULL);

      list = gvdb_table_list (table, key);
      g_assert (list == NULL);
    }

  gvdb_table_unref (table);
}

static void
verify_table (GvdbTable *table)
{
  GVariant *value;
  gchar **list;
  gboolean has;

  list = gvdb_table_list (table, "/");
  g_assert (list != NULL);
  g_assert_cmpint (g_strv_length (list), ==, 1);
  g_assert_cmpstr (list[0], ==, "values/");
  g_strfreev (list);

  list = gvdb_table_list (table, "/values/");
  g_assert (list != NULL);
  g_assert_cmpint (g_strv_length (list), ==, 3);
  g_assert_cmpstr (list[0], ==, "boolean");
  g_assert_cmpstr (list[1], ==, "int32");
  g_assert_cmpstr (list[2], ==, "string");
  g_strfreev (list);

  /* A directory is not a value */
  has = gvdb_table_has_value (table, "/");
  g_assert (!has);
  has = gvdb_table_has_value (table, "/values/");
  g_assert (!has);

  has = gvdb_table_has_value (table, "/int32");
  g_assert (!has);
  has = gvdb_table_has_value (table, "values/int32");
  g_assert (!has);
  has = gvdb_table_has_value (table, "/values/int32");
  g_assert (has);

  value = gvdb_table_get_value (table, "/");
  g_assert (value == NULL);
  value = gvdb_table_get_value (table, "/values/");
  g_assert (value == NULL);
  value = gvdb_table_get_value (table, "/int32");
  g_assert (value == NULL);
  value = gvdb_table_get_value (table, "values/int32");
  g_assert (value == NULL);

  value = gvdb_table_get_value (table, "/values/boolean");
  g_assert (value != NULL && g_variant_is_of_type (value, G_VARIANT_TYPE_BOOLEAN));
  g_assert (g_variant_get_boolean (value));
  g_variant_unref (value);

  value = gvdb_table_get_raw_value (table, "/values/boolean");
  g_assert (value != NULL && g_variant_is_of_type (value, G_VARIANT_TYPE_BOOLEAN));
  g_assert (g_variant_get_boolean (value));
  g_variant_unref (value);

  value = gvdb_table_get_value (table, "/values/int32");
  g_assert (value != NULL && g_variant_is_of_type (value, G_VARIANT_TYPE_INT32));
  g_assert_cmpint (g_variant_get_int32 (value), ==, 0x44332211);
  g_variant_unref (value);

  value = gvdb_table_get_value (table, "/values/string");
  g_assert (value != NULL && g_variant_is_of_type (value, G_VARIANT_TYPE_STRING));
  g_assert_cmpstr (g_variant_get_string (value, NULL), ==, "a string");
  g_variant_unref (value);

  value = gvdb_table_get_raw_value (table, "/values/string");
  g_assert (value != NULL && g_variant_is_of_type (value, G_VARIANT_TYPE_STRING));
  g_assert_cmpstr (g_variant_get_string (value, NULL), ==, "a string");
  g_variant_unref (value);
}

static void
test_reader_values (void)
{
  GError *error = NULL;
  GvdbTable *table;

  table = gvdb_table_new (SRCDIR "/gvdbs/example_gvdb", TRUE, &error);
  g_assert_no_error (error);
  verify_table (table);

#if G_BYTE_ORDER == G_BIG_ENDIAN
  {
    GVariant *value;

    value = gvdb_table_get_raw_value (table, "/values/int32");
    g_assert (value != NULL && g_variant_is_of_type (value, G_VARIANT_TYPE_INT32));
    g_assert_cmpint (g_variant_get_int32 (value), ==, 0x11223344);
    g_variant_unref (value);
  }
#endif

  gvdb_table_unref (table);
}

static void
test_reader_values_bigendian (void)
{
  GError *error = NULL;
  GvdbTable *table;

  table = gvdb_table_new (SRCDIR "/gvdbs/example_gvdb.big-endian", TRUE, &error);
  g_assert_no_error (error);
  verify_table (table);

#if G_BYTE_ORDER == G_LITTLE_ENDIAN
  {
    GVariant *value;

    value = gvdb_table_get_raw_value (table, "/values/int32");
    g_assert (value != NULL && g_variant_is_of_type (value, G_VARIANT_TYPE_INT32));
    g_assert_cmpint (g_variant_get_int32 (value), ==, 0x11223344);
    g_variant_unref (value);
  }
#endif

  gvdb_table_unref (table);
}

static gint accept_this_many_opens;

static gboolean
walk_open (const gchar *name,
           gsize        name_len,
           gpointer     user_data)
{
  GString *log = user_data;

  g_string_append (log, "'");
  g_string_append_len (log, name, name_len);
  g_string_append_printf (log, "\'(%zd): {", name_len);

  if (accept_this_many_opens)
    {
      if (accept_this_many_opens > 0)
        accept_this_many_opens--;
      return TRUE;
    }

  g_string_append (log, "rejected}");

  return FALSE;
}

static void
walk_value (const gchar *name,
            gsize        name_len,
            GVariant    *value,
            gpointer     user_data)
{
  GString *log = user_data;
  gchar *printed;

  printed = g_variant_print (value, FALSE);

  g_string_append (log, "'");
  g_string_append_len (log, name, name_len);
  g_string_append_printf (log, "\'(%zd): %s", name_len, printed);
  g_free (printed);
}

static void
walk_close (gsize    name_len,
            gpointer user_data)
{
  GString *log = user_data;

  g_string_append_printf (log, "(%zd)}", name_len);
}

static void
verify_walk (GvdbTable *table)
{
  GString *log;

  log = g_string_new (NULL);
  accept_this_many_opens = 2;
  gvdb_table_walk (table, "/", walk_open, walk_value, walk_close, log);
  g_assert_cmpstr (log->str, ==,
                   "'/'(1): {"
                     "'values/'(7): {"
                       "'boolean'(7): true"
                       "'int32'(5): 1144201745"
                       "'string'(6): 'a string'"
                     "(7)}"
                   "(1)}");
  g_string_truncate (log, 0);

  accept_this_many_opens = 1;
  gvdb_table_walk (table, "/", walk_open, walk_value, walk_close, log);
  g_assert_cmpstr (log->str, ==,
                   "'/'(1): {"
                     "'values/'(7): {rejected}"
                   "(1)}");
  g_string_truncate (log, 0);

  accept_this_many_opens = 0;
  gvdb_table_walk (table, "/", walk_open, walk_value, walk_close, log);
  g_assert_cmpstr (log->str, ==, "'/'(1): {rejected}");
  g_string_free (log, TRUE);
}

static void
test_reader_walk (void)
{
  GError *error = NULL;
  GvdbTable *table;

  table = gvdb_table_new (SRCDIR "/gvdbs/example_gvdb", TRUE, &error);
  g_assert_no_error (error);

  verify_walk (table);

  gvdb_table_unref (table);
}

static void
test_reader_walk_bigendian (void)
{
  GError *error = NULL;
  GvdbTable *table;

  table = gvdb_table_new (SRCDIR "/gvdbs/example_gvdb.big-endian", TRUE, &error);
  g_assert_no_error (error);

  verify_walk (table);

  gvdb_table_unref (table);
}

static void
test_nested (void)
{
  GError *error = NULL;
  GvdbTable *table;
  GvdbTable *locks;
  gboolean has;

  table = gvdb_table_new (SRCDIR "/gvdbs/nested_gvdb", TRUE, &error);
  g_assert_no_error (error);

  verify_walk (table);

  locks = gvdb_table_get_table (table, "/");
  g_assert (locks == NULL);
  locks = gvdb_table_get_table (table, "/values/");
  g_assert (locks == NULL);
  locks = gvdb_table_get_table (table, "/values/int32");
  g_assert (locks == NULL);

  locks = gvdb_table_get_table (table, ".locks");
  g_assert (locks != NULL);

  has = gvdb_table_has_value (locks, "/first/lck");
  g_assert (!has);

  has = gvdb_table_has_value (locks, "/first/lock");
  g_assert (has);

  has = gvdb_table_has_value (locks, "/second");
  g_assert (has);

  gvdb_table_unref (table);
}

/* This function exercises the API against @table but does not do any
 * asserts on unexpected values (although it will assert on inconsistent
 * values returned by the API).
 */
static void
inspect_carefully (GvdbTable *table)
{
  const gchar * key_names[] = {
    "/", "/values/", "/int32", "values/int32",
    "/values/int32", "/values/boolean", "/values/string",
    ".locks", "/first/lock", "/second", NULL
  };
  GString *log;
  gint i;

  for (i = 0; key_names[i]; i++)
    {
      const gchar *key = key_names[i];
      GvdbTable *subtable;
      GVariant *value;
      gchar **list;
      gboolean has;

      has = gvdb_table_has_value (table, key);

      list = gvdb_table_list (table, key);
      g_assert (!has || list == NULL);
      if (list)
        {
          gchar *joined = g_strjoinv (",", list);
          g_strfreev (list);
          g_free (joined);
        }

      value = gvdb_table_get_value (table, key);
      g_assert_cmpint (value != NULL, ==, has);
      if (value)
        {
          gchar *printed = g_variant_print (value, FALSE);
          g_variant_unref (value);
          g_free (printed);
        }

      value = gvdb_table_get_raw_value (table, key);
      g_assert_cmpint (value != NULL, ==, has);
      if (value)
        {
          gchar *printed = g_variant_print (value, FALSE);
          g_variant_unref (value);
          g_free (printed);
        }

      subtable = gvdb_table_get_table (table, key);
      g_assert (!has || subtable == NULL);
      if (subtable)
        {
          inspect_carefully (subtable);
          gvdb_table_unref (subtable);
        }
    }

  log = g_string_new (NULL);
  accept_this_many_opens = -1;
  gvdb_table_walk (table, "/", walk_open, walk_value, walk_close, log);
  g_string_free (log, TRUE);
}

static void
test_corrupted (gconstpointer user_data)
{
  gint percentage = GPOINTER_TO_INT (user_data);
  GError *error = NULL;
  GMappedFile *mapped;

  mapped = g_mapped_file_new (SRCDIR "/gvdbs/nested_gvdb", FALSE, &error);
  g_assert_no_error (error);
  g_assert (mapped);

  if (percentage)
    {
      GvdbTable *table;
      const gchar *orig;
      gsize length;
      gchar *copy;
      gint i;

      orig = g_mapped_file_get_contents (mapped);
      length = g_mapped_file_get_length (mapped);
      copy = g_memdup (orig, length);

      for (i = 0; i < 10000; i++)
        {
          gint j;

          /* Make a broken copy, but leave the signature intact so that
           * we don't get too many boring trivial failures.
           */
          for (j = 8; j < length; j++)
            if (g_test_rand_int_range (0, 100) < percentage)
              copy[j] = g_test_rand_int_range (0, 256);
            else
              copy[j] = orig[j];

          table = gvdb_table_new_from_data (copy, length, FALSE, NULL, NULL, NULL, &error);

          /* If we damaged the header, it may not open */
          if (table)
            {
              inspect_carefully (table);
              gvdb_table_unref (table);
            }
          else
            {
              g_assert_error (error, G_FILE_ERROR, G_FILE_ERROR_INVAL);
              g_clear_error (&error);
            }
        }
    }
  else
    {
      GvdbTable *table;

      table = gvdb_table_new_from_data (g_mapped_file_get_contents (mapped),
                                        g_mapped_file_get_length (mapped),
                                        FALSE, NULL, NULL, NULL, &error);
      g_assert_no_error (error);
      g_assert (table);

      inspect_carefully (table);
      gvdb_table_unref (table);
    }

  g_mapped_file_unref (mapped);
}

int
main (int argc, char **argv)
{
  gint i;

  g_test_init (&argc, &argv, NULL);

  g_test_add_func ("/gvdb/reader/open-error", test_reader_open_error);
  g_test_add_func ("/gvdb/reader/empty", test_reader_empty);
  g_test_add_func ("/gvdb/reader/values", test_reader_values);
  g_test_add_func ("/gvdb/reader/values/big-endian", test_reader_values_bigendian);
  g_test_add_func ("/gvdb/reader/walk", test_reader_walk);
  g_test_add_func ("/gvdb/reader/walk/big-endian", test_reader_walk_bigendian);
  g_test_add_func ("/gvdb/reader/nested", test_nested);
  for (i = 0; i < 20; i++)
    {
      gchar test_name[80];
      g_snprintf (test_name, sizeof test_name, "/gvdb/reader/corrupted/%d%%", i);
      g_test_add_data_func (test_name, GINT_TO_POINTER (i), test_corrupted);
    }

  return g_test_run ();
}
