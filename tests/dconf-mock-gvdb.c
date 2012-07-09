#include "../gvdb/gvdb-reader.h"

void
gvdb_table_unref (GvdbTable *table)
{
}

GvdbTable *
gvdb_table_get_table (GvdbTable   *table,
                      const gchar *key)
{
  return NULL;
}

gboolean
gvdb_table_has_value (GvdbTable   *table,
                      const gchar *key)
{
  return FALSE;
}

GVariant *
gvdb_table_get_value (GvdbTable   *table,
                      const gchar *key)
{
  return NULL;
}

gchar **
gvdb_table_list (GvdbTable *table,
                 const gchar *key)
{
  return NULL;
}

GvdbTable *
gvdb_table_new (const gchar  *filename,
                gboolean      trusted,
                GError      **error)
{
  g_set_error_literal (error, G_FILE_ERROR, G_FILE_ERROR_FAILED, "not implemented");
  return NULL;
}

gboolean
gvdb_table_is_valid (GvdbTable *table)
{
  return TRUE;
}
