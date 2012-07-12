#include "../shm/dconf-shm.h"

#include "dconf-mock.h"

typedef struct
{
  guint8 flagged;
  gint   ref_count;
} DConfMockShm;

static GHashTable *dconf_mock_shm_table;
static GMutex      dconf_mock_shm_lock;
static GString    *dconf_mock_shm_log;

static void
dconf_mock_shm_unref (gpointer data)
{
  DConfMockShm *shm = data;

  if (g_atomic_int_dec_and_test (&shm->ref_count))
    g_slice_free (DConfMockShm, shm);
}

static DConfMockShm *
dconf_mock_shm_ref (DConfMockShm *shm)
{
  g_atomic_int_inc (&shm->ref_count);

  return shm;
}

guint8 *
dconf_shm_open (const gchar *name)
{
  DConfMockShm *shm;

  g_mutex_lock (&dconf_mock_shm_lock);

  if G_UNLIKELY (dconf_mock_shm_table == NULL)
    {
      dconf_mock_shm_table = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, dconf_mock_shm_unref);
      dconf_mock_shm_log = g_string_new (NULL);
    }

  shm = g_hash_table_lookup (dconf_mock_shm_table, name);
  if (shm == NULL)
    {
      shm = g_slice_new0 (DConfMockShm);
      g_hash_table_insert (dconf_mock_shm_table, g_strdup (name), dconf_mock_shm_ref (shm));
    }

  /* before unlocking... */
  dconf_mock_shm_ref (shm);

  g_string_append_printf (dconf_mock_shm_log, "open %s;", name);

  g_mutex_unlock (&dconf_mock_shm_lock);

  return &shm->flagged;
}

void
dconf_shm_close (guint8 *shm)
{
  if (shm)
    {
      g_mutex_lock (&dconf_mock_shm_lock);
      g_string_append (dconf_mock_shm_log, "close;");
      g_mutex_unlock (&dconf_mock_shm_lock);

      dconf_mock_shm_unref (shm);
    }
}

gint
dconf_mock_shm_flag (const gchar *name)
{
  DConfMockShm *shm;
  gint count = 0;

  g_mutex_lock (&dconf_mock_shm_lock);
  shm = g_hash_table_lookup (dconf_mock_shm_table, name);
  if (shm)
    {
      shm->flagged = 1;
      count = shm->ref_count;
      g_hash_table_remove (dconf_mock_shm_table, name);
    }
  g_mutex_unlock (&dconf_mock_shm_lock);

  return count;
}

void
dconf_mock_shm_reset (void)
{
  g_mutex_lock (&dconf_mock_shm_lock);
  if (dconf_mock_shm_table != NULL)
    {
      GHashTableIter iter;
      gpointer value;

      g_hash_table_iter_init (&iter, dconf_mock_shm_table);
      while (g_hash_table_iter_next (&iter, NULL, &value))
        {
          DConfMockShm *shm = value;

          g_assert_cmpint (shm->ref_count, ==, 1);
          g_hash_table_iter_remove (&iter);
        }

      g_string_truncate (dconf_mock_shm_log, 0);
    }
  g_mutex_unlock (&dconf_mock_shm_lock);
}

void
dconf_mock_shm_assert_log (const gchar *expected_log)
{
  g_mutex_lock (&dconf_mock_shm_lock);
  g_assert_cmpstr (dconf_mock_shm_log->str, ==, expected_log);
  g_string_truncate (dconf_mock_shm_log, 0);
  g_mutex_unlock (&dconf_mock_shm_lock);
}
