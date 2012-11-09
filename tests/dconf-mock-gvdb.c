#include "../gvdb/gvdb-reader.h"
#include "dconf-mock.h"

/* The global dconf_mock_gvdb_tables hashtable is modified all the time
 * so we need to hold the lock while we access it.
 *
 * The hashtables contained within it are never modified, however.  They
 * can be safely accessed without a lock.
 */

static GHashTable *dconf_mock_gvdb_tables;
static GMutex      dconf_mock_gvdb_lock;

typedef struct
{
  GVariant  *value;
  GvdbTable *table;
} DConfMockGvdbItem;

struct _GvdbTable
{
  GHashTable *table;
  gboolean    is_valid;
  gboolean    top_level;
  gint        ref_count;
};

static void
dconf_mock_gvdb_item_free (gpointer data)
{
  DConfMockGvdbItem *item = data;

  if (item->value)
    g_variant_unref (item->value);

  if (item->table)
    gvdb_table_free (item->table);

  g_slice_free (DConfMockGvdbItem, item);
}

static void
dconf_mock_gvdb_init (void)
{
  if (dconf_mock_gvdb_tables == NULL)
    dconf_mock_gvdb_tables = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, (GDestroyNotify) gvdb_table_free);
}

GvdbTable *
dconf_mock_gvdb_table_new (void)
{
  GvdbTable *table;

  table = g_slice_new (GvdbTable);
  table->table = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, dconf_mock_gvdb_item_free);
  table->ref_count = 1;
  table->is_valid = TRUE;

  return table;
}

void
dconf_mock_gvdb_table_insert (GvdbTable   *table,
                              const gchar *name,
                              GVariant    *value,
                              GvdbTable   *subtable)
{
  DConfMockGvdbItem *item;

  g_assert (value == NULL || subtable == NULL);

  if (subtable)
    subtable->top_level = FALSE;

  item = g_slice_new (DConfMockGvdbItem);
  item->value = value ? g_variant_ref_sink (value) : NULL;
  item->table = subtable;

  g_hash_table_insert (table->table, g_strdup (name), item);
}

void
dconf_mock_gvdb_install (const gchar *filename,
                         GvdbTable   *table)
{
  g_mutex_lock (&dconf_mock_gvdb_lock);
  dconf_mock_gvdb_init ();

  if (table)
    {
      table->top_level = TRUE;
      g_hash_table_insert (dconf_mock_gvdb_tables, g_strdup (filename), table);
    }
  else
    g_hash_table_remove (dconf_mock_gvdb_tables, filename);

  g_mutex_unlock (&dconf_mock_gvdb_lock);
}

void
gvdb_table_free (GvdbTable *table)
{
  if (g_atomic_int_dec_and_test (&table->ref_count))
    {
      g_hash_table_unref (table->table);
      g_slice_free (GvdbTable, table);
    }
}

GvdbTable *
dconf_mock_gvdb_table_ref (GvdbTable *table)
{
  g_atomic_int_inc (&table->ref_count);

  return table;
}

GvdbTable *
gvdb_table_get_table (GvdbTable   *table,
                      const gchar *key)
{
  DConfMockGvdbItem *item;
  GvdbTable *subtable;

  item = g_hash_table_lookup (table->table, key);

  if (item && item->table)
    subtable = dconf_mock_gvdb_table_ref (item->table);
  else
    subtable = NULL;

  return subtable;
}

gboolean
gvdb_table_has_value (GvdbTable   *table,
                      const gchar *key)
{
  DConfMockGvdbItem *item;

  item = g_hash_table_lookup (table->table, key);

  return item && item->value;
}

GVariant *
gvdb_table_get_value (GvdbTable   *table,
                      const gchar *key)
{
  DConfMockGvdbItem *item;

  item = g_hash_table_lookup (table->table, key);

  return (item && item->value) ? g_variant_ref (item->value) : NULL;
}

gchar **
gvdb_table_list (GvdbTable   *table,
                 const gchar *key)
{
  const gchar * const result[] = { "value", NULL };

  g_assert_cmpstr (key, ==, "/");

  if (!gvdb_table_has_value (table, "/value"))
    return NULL;

  return g_strdupv ((gchar **) result);
}

GvdbTable *
gvdb_table_new (const gchar  *filename,
                gboolean      trusted,
                GError      **error)
{
  GvdbTable *table;

  g_mutex_lock (&dconf_mock_gvdb_lock);
  dconf_mock_gvdb_init ();
  table = g_hash_table_lookup (dconf_mock_gvdb_tables, filename);
  if (table)
    dconf_mock_gvdb_table_ref (table);
  g_mutex_unlock (&dconf_mock_gvdb_lock);

  if (table == NULL)
    g_set_error (error, G_FILE_ERROR, G_FILE_ERROR_NOENT, "this gvdb does not exist");

  return table;
}

gboolean
gvdb_table_is_valid (GvdbTable *table)
{
  return table->is_valid;
}

void
dconf_mock_gvdb_table_invalidate (GvdbTable *table)
{
  table->is_valid = FALSE;
}
