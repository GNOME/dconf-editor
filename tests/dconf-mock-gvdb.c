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
  GVariant   *value;
  GHashTable *table;
} DConfMockGvdbItem;

static void
dconf_mock_gvdb_item_free (gpointer data)
{
  DConfMockGvdbItem *item = data;

  if (item->value)
    g_variant_unref (item->value);

  if (item->table)
    g_hash_table_unref (item->table);

  g_slice_free (DConfMockGvdbItem, item);
}

static void
dconf_mock_gvdb_init (void)
{
  if (dconf_mock_gvdb_tables == NULL)
    dconf_mock_gvdb_tables = g_hash_table_new_full (g_str_hash, g_str_equal, g_free,
                                                    (GDestroyNotify) g_hash_table_unref);
}

DConfMockGvdbTable *
dconf_mock_gvdb_table_new (void)
{
  GHashTable *hash_table;

  hash_table = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, dconf_mock_gvdb_item_free);

  return (DConfMockGvdbTable *) hash_table;
}

void
dconf_mock_gvdb_table_insert (DConfMockGvdbTable *table,
                              const gchar        *name,
                              GVariant           *value,
                              DConfMockGvdbTable *subtable)
{
  GHashTable *hash_table = (GHashTable *) table;
  DConfMockGvdbItem *item;

  g_assert (value == NULL || subtable == NULL);

  item = g_slice_new (DConfMockGvdbItem);
  item->value = value ? g_variant_ref_sink (value) : NULL;
  item->table = (GHashTable *) subtable;

  g_hash_table_insert (hash_table, g_strdup (name), item);
}

void
dconf_mock_gvdb_install (const gchar        *filename,
                         DConfMockGvdbTable *table)
{
  g_mutex_lock (&dconf_mock_gvdb_lock);
  dconf_mock_gvdb_init ();

  if (table)
    g_hash_table_insert (dconf_mock_gvdb_tables, g_strdup (filename), table);
  else
    g_hash_table_remove (dconf_mock_gvdb_tables, filename);

  g_mutex_unlock (&dconf_mock_gvdb_lock);
}

void
gvdb_table_unref (GvdbTable *table)
{
  GHashTable *hash_table = (GHashTable *) table;

  g_hash_table_unref (hash_table);
}

GvdbTable *
gvdb_table_get_table (GvdbTable   *table,
                      const gchar *key)
{
  GHashTable *hash_table = (GHashTable *) table;
  DConfMockGvdbItem *item;

  item = g_hash_table_lookup (hash_table, key);

  return (GvdbTable *) (item ? g_hash_table_ref (item->table) : NULL);
}

gboolean
gvdb_table_has_value (GvdbTable   *table,
                      const gchar *key)
{
  GHashTable *hash_table = (GHashTable *) table;
  DConfMockGvdbItem *item;

  item = g_hash_table_lookup (hash_table, key);

  return item && item->value;
}

GVariant *
gvdb_table_get_value (GvdbTable   *table,
                      const gchar *key)
{
  GHashTable *hash_table = (GHashTable *) table;
  DConfMockGvdbItem *item;

  item = g_hash_table_lookup (hash_table, key);

  return item ? g_variant_ref (item->value) : NULL;
}

gchar **
gvdb_table_list (GvdbTable *table,
                 const gchar *key)
{
  g_assert_not_reached ();
}

GvdbTable *
gvdb_table_new (const gchar  *filename,
                gboolean      trusted,
                GError      **error)
{
  GHashTable *hash_table;

  g_mutex_lock (&dconf_mock_gvdb_lock);
  dconf_mock_gvdb_init ();
  hash_table = g_hash_table_lookup (dconf_mock_gvdb_tables, filename);
  if (hash_table)
      g_hash_table_ref (hash_table);
  g_mutex_unlock (&dconf_mock_gvdb_lock);

  if (hash_table == NULL)
    g_set_error (error, G_FILE_ERROR, G_FILE_ERROR_NOENT, "this gvdb does not exist");

  return (GvdbTable *) hash_table;
}

gboolean
gvdb_table_is_valid (GvdbTable *table)
{
  return TRUE;
}
