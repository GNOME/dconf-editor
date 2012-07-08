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
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

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

  if (ftruncate (fd, 1) != 0)
    {
      g_critical ("failed to allocate file '%s': %s.  dconf will not work properly.", filename, g_strerror (errno));
      goto out;
    }

  memory = mmap (NULL, 1, PROT_READ, MAP_SHARED, fd, 0);
  g_assert (memory != NULL);

  if (memory == MAP_FAILED)
    {
      g_critical ("failed to mmap file '%s': %s.  dconf will not work properly.", filename, g_strerror (errno));
      memory = NULL;
      goto out;
    }

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

  fd = open (filename, O_WRONLY);
  if (fd >= 0)
    {
      guint8 *shm;

      /* Easiest thing to do here would be write(fd, "\1", 1); but this
       * causes problems on kernels (ie: OpenBSD) that don't sync up
       * their filesystem cache with mmap()ed regions.
       *
       * Using mmap() works everywhere.
       */
      shm = mmap (NULL, 1, PROT_WRITE, MAP_SHARED, fd, 0);

      if (shm != MAP_FAILED)
        {
          *shm = 1;

          munmap (shm, 1);
        }
      else
        g_warning ("failed to invalidate mmap file '%s': %s.", filename, g_strerror (errno));

      close (fd);

      unlink (filename);
    }

  else if (errno != ENOENT)
    unlink (filename);

  g_free (filename);
}
