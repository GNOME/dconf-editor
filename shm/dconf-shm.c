/*
 * Copyright © 2010 Codethink Limited
 * Copyright © 2012 Canonical Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the licence, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "config.h"

#include "dconf-shm.h"

#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static gchar *
dconf_shm_get_shmdir (void)
{
  static gchar *shmdir;

  if (g_once_init_enter (&shmdir))
    g_once_init_leave (&shmdir, g_build_filename (g_get_user_runtime_dir (), "dconf", NULL));

  return shmdir;
}

void
dconf_shm_close (guint8 *shm)
{
  if (shm)
    munmap (shm, 1);
}

guint8 *
dconf_shm_open (const gchar *name)
{
  const gchar *shmdir;
  gchar *filename;
  void *memory;
  gint fd;

  shmdir = dconf_shm_get_shmdir ();
  filename = g_build_filename (shmdir, name, NULL);
  memory = NULL;
  fd = -1;

  if (g_mkdir_with_parents (shmdir, 0700) != 0)
    {
      g_critical ("unable to create directory '%s': %s.  dconf will not work properly.", shmdir, g_strerror (errno));
      goto out;
    }

  fd = open (filename, O_RDWR | O_CREAT, 0600);
  if (fd == -1)
    {
      g_critical ("unable to create file '%s': %s.  dconf will not work properly.", filename, g_strerror (errno));
      goto out;
    }

  /* ftruncate(fd, 1) is not sufficient because it does not actually
   * ensure that the space is available (which could give a SIGBUS
   * later).
   *
   * posix_fallocate() is also problematic because it is implemented in
   * a racy way in the libc if unavailable for a particular filesystem
   * (as is the case for tmpfs, which is where we probably are).
   *
   * By writing to the second byte in the file we ensure we don't
   * overwrite the first byte (which is the one we care about).
   */
  if (pwrite (fd, "", 1, 1) != 1)
    {
      g_critical ("failed to allocate file '%s': %s.  dconf will not work properly.", filename, g_strerror (errno));
      goto out;
    }

  memory = mmap (NULL, 1, PROT_READ, MAP_SHARED, fd, 0);
  g_assert (memory != MAP_FAILED);
  g_assert (memory != NULL);

 out:
  g_free (filename);
  close (fd);

  return memory;
}

void
dconf_shm_flag (const gchar *name)
{
  const gchar *shmdir;
  gchar *filename;
  gint fd;

  shmdir = dconf_shm_get_shmdir ();
  filename = g_build_filename (shmdir, name, NULL);

  /* We need O_RDWR for PROT_WRITE.
   *
   * This is probably due to the fact that some architectures can't make
   * write-only mappings (so they end up being readable as well).
   */
  fd = open (filename, O_RDWR);
  if (fd >= 0)
    {
      /* In theory we could have opened the file after a client created
       * it but before they called pwrite().  Do the pwrite() ourselves
       * to make sure (so we don't get SIGBUS in a moment).
       *
       * If this fails then it will probably fail for the client too.
       * If it doesn't then there's not really much we can do...
       */
      if (pwrite (fd, "", 1, 1) == 1)
        {
          guint8 *shm;

          /* It would have been easier for us to do write(fd, "\1", 1);
           * but this causes problems on kernels (ie: OpenBSD) that
           * don't sync up their filesystem cache with mmap()ed regions.
           *
           * Using mmap() works everywhere.
           *
           * See https://bugzilla.gnome.org/show_bug.cgi?id=687334 about
           * why we need to have PROT_READ even though we only write.
           */
          shm = mmap (NULL, 1, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
          g_assert (shm != MAP_FAILED);

          *shm = 1;

          munmap (shm, 1);
        }

      close (fd);

      unlink (filename);
    }

  g_free (filename);
}
