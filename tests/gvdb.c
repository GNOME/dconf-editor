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
  gchar **names;
  gint n_names;
  gint i;

  table = gvdb_table_new (SRCDIR "/gvdbs/empty_gvdb", TRUE, &error);
  g_assert_no_error (error);
  g_assert (table != NULL);

  g_assert (gvdb_table_is_valid (table));

  names = gvdb_table_get_names (table, &n_names);
  g_assert_cmpint (n_names, ==, 0);
  g_assert_cmpint (g_strv_length (names), ==, 0);
  g_strfreev (names);

  names = gvdb_table_get_names (table, NULL);
  g_assert_cmpint (g_strv_length (names), ==, 0);
  g_strfreev (names);

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

  gvdb_table_free (table);
}

static void
verify_table (GvdbTable *table)
{
  GVariant *value;
  gchar **list;
  gint n_names;
  gboolean has;

  /* We could not normally expect these to be in a particular order but
   * we are using a specific test file that we know to be layed out this
   * way...
   *
   * It's pure luck that they happened to be layed out in this nice way.
   */
  list = gvdb_table_get_names (table, &n_names);
  g_assert_cmpint (n_names, ==, g_strv_length (list));
  g_assert_cmpint (n_names, ==, 5);
  g_assert_cmpstr (list[0], ==, "/");
  g_assert_cmpstr (list[1], ==, "/values/");
  g_assert_cmpstr (list[2], ==, "/values/boolean");
  g_assert_cmpstr (list[3], ==, "/values/string");
  g_assert_cmpstr (list[4], ==, "/values/int32");
  g_strfreev (list);

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

  gvdb_table_free (table);
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

  gvdb_table_free (table);
}

static void
test_nested (void)
{
  GError *error = NULL;
  GvdbTable *table;
  GvdbTable *locks;
  gchar **names;
  gint n_names;
  gboolean has;

  table = gvdb_table_new (SRCDIR "/gvdbs/nested_gvdb", TRUE, &error);
  g_assert_no_error (error);

  /* Note the more-random ordering here compared with above. */
  names = gvdb_table_get_names (table, &n_names);
  g_assert_cmpint (n_names, ==, g_strv_length (names));
  g_assert_cmpint (n_names, ==, 6);
  g_assert_cmpstr (names[0], ==, "/values/boolean");
  g_assert_cmpstr (names[1], ==, "/");
  g_assert_cmpstr (names[2], ==, "/values/int32");
  g_assert_cmpstr (names[3], ==, ".locks");
  g_assert_cmpstr (names[4], ==, "/values/");
  g_assert_cmpstr (names[5], ==, "/values/string");
  g_strfreev (names);

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

  gvdb_table_free (table);
  gvdb_table_free (locks);
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
  gint found_items;
  gchar **names;
  gint n_names;
  gint i;

  found_items = 0;
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
          found_items++;
        }

      value = gvdb_table_get_value (table, key);
      g_assert_cmpint (value != NULL, ==, has);
      if (value)
        {
          gchar *printed = g_variant_print (value, FALSE);
          g_variant_unref (value);
          g_free (printed);
          found_items++;
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
          gvdb_table_free (subtable);
          found_items++;
        }
    }

  names = gvdb_table_get_names (table, &n_names);
  g_assert_cmpint (n_names, ==, g_strv_length (names));
  g_assert_cmpint (found_items, <=, n_names);
  g_free (g_strjoinv ("  ", names));
  g_strfreev (names);
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
          GBytes *bytes;
          gint j;

          /* Make a broken copy, but leave the signature intact so that
           * we don't get too many boring trivial failures.
           */
          for (j = 8; j < length; j++)
            if (g_test_rand_int_range (0, 100) < percentage)
              copy[j] = g_test_rand_int_range (0, 256);
            else
              copy[j] = orig[j];

          bytes = g_bytes_new_static (copy, length);
          table = gvdb_table_new_from_bytes (bytes, FALSE, &error);
          g_bytes_unref (bytes);

          /* If we damaged the header, it may not open */
          if (table)
            {
              inspect_carefully (table);
              gvdb_table_free (table);
            }
          else
            {
              g_assert_error (error, G_FILE_ERROR, G_FILE_ERROR_INVAL);
              g_clear_error (&error);
            }
        }

      g_free (copy);
    }
  else
    {
      GvdbTable *table;
      GBytes *bytes;

      bytes = g_mapped_file_get_bytes (mapped);
      table = gvdb_table_new_from_bytes (bytes, FALSE, &error);
      g_bytes_unref (bytes);

      g_assert_no_error (error);
      g_assert (table);

      inspect_carefully (table);
      gvdb_table_free (table);
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
  g_test_add_func ("/gvdb/reader/nested", test_nested);
  for (i = 0; i < 20; i++)
    {
      gchar test_name[80];
      g_snprintf (test_name, sizeof test_name, "/gvdb/reader/corrupted/%d%%", i);
      g_test_add_data_func (test_name, GINT_TO_POINTER (i), test_corrupted);
    }

  return g_test_run ();
}
