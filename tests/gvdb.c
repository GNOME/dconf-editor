#include <glib.h>
#include "gvdb-reader.h"

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

  g_string_append_c (log, '\'');
  g_string_append_len (log, name, name_len);
  g_string_append_printf (log, "\'(%zd): {", name_len);

  if (accept_this_many_opens)
    {
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

  g_string_append_c (log, '\'');
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

int
main (int argc, char **argv)
{
  g_test_init (&argc, &argv, NULL);

  g_test_add_func ("/gvdb/reader/open-error", test_reader_open_error);
  g_test_add_func ("/gvdb/reader/empty", test_reader_empty);
  g_test_add_func ("/gvdb/reader/values", test_reader_values);
  g_test_add_func ("/gvdb/reader/values/big-endian", test_reader_values_bigendian);
  g_test_add_func ("/gvdb/reader/walk", test_reader_walk);
  g_test_add_func ("/gvdb/reader/walk/big-endian", test_reader_walk_bigendian);

  return g_test_run ();
}
