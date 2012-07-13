#include "tmpdir.h"

#include <glib/gstdio.h>
#include "../common/dconf-paths.h"
#include <string.h>

gchar *
dconf_test_create_tmpdir (void)
{
  GError *error = NULL;
  gchar *temp;

  temp = g_dir_make_tmp ("dconf-testcase.XXXXXX", &error);
  g_assert_no_error (error);
  g_assert (temp != NULL);

  return temp;
}

static void
rm_rf (const gchar *file)
{
  GDir *dir;

  dir = g_dir_open (file, 0, NULL);
  if (dir)
    {
      const gchar *basename;

      while ((basename = g_dir_read_name (dir)))
        {
          gchar *fullname;

          fullname = g_build_filename (file, basename, NULL);
          rm_rf (fullname);
          g_free (fullname);
        }

      g_dir_close (dir);
      g_rmdir (file);
    }

  else
    /* excess paranoia -- only unlink if we're really really sure */
    if (strstr (file, "/dconf-testcase") && !strstr (file, ".."))
      g_unlink (file);
}

void
dconf_test_remove_tmpdir (const gchar *tmpdir)
{
  rm_rf (tmpdir);
}
