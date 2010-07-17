#include "dconf-shmdir.h"

#include <sys/statfs.h>
#include <sys/vfs.h>
#include <errno.h>

#ifndef NFS_SUPER_MAGIC
#define NFS_SUPER_MAGIC 0x6969
#endif

static gboolean
is_local (const gchar *filename)
{
  struct statfs buf;
  gint s;

  do
    s = statfs (filename, &buf);
  while (s < 0 && errno == EINTR);

  if (s < 0 && errno == ENOENT)
    {
      g_mkdir_with_parents (filename, 0700);

      do
        s = statfs (filename, &buf);
      while (s < 0 && errno == EINTR);
    }

  return s == 0 && buf.f_type != NFS_SUPER_MAGIC;
}

gchar *
dconf_shmdir_from_environment (void)
{
  gchar *result;

  result = g_strdup (g_getenv ("DCONF_SESSION_DIR"));

  if (result == NULL)
    {
      const gchar *cache = g_get_user_cache_dir ();

      if (is_local (cache))
        {
          result = g_build_filename (cache, "dconf", NULL);

          if (g_mkdir_with_parents (result, 0700) != 0)
            {
              g_free (result);
              result = NULL;
            }
        }
    }

  return result;
}
