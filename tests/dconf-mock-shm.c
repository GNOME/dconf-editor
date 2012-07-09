#include "../shm/dconf-shm.h"

guint8 *
dconf_shm_open (const gchar *name)
{
  return g_malloc0 (1);
}

void
dconf_shm_close (guint8 *shm)
{
  g_free (shm);
}
