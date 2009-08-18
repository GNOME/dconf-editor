/*
 * Copyright © 2009 Codethink Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#include "dconf-writer-private.h"

#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <errno.h>

static gboolean
dconf_writer_create_directory (const gchar  *filename,
                               GError      **error)
{
  gchar *dirname;

  dirname = g_path_get_dirname (filename);

  if (g_mkdir_with_parents (dirname, 0777))
    {
      gint saved_errno = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "failed to create directory %s: %s",
                   dirname, g_strerror (saved_errno));
      g_free (dirname);

      return FALSE;
    }

  g_free (dirname);

  return TRUE;
}

static gpointer
dconf_writer_create_temp_file (const gchar  *filename,
                               gint         *fd,
                               gint          bytes,
                               gchar       **tmpname,
                               GError      **error)
{
  gpointer contents;
  gint saved_errno;

  *tmpname = g_strdup_printf ("%s.XXXXXX", filename);

  if ((*fd = g_mkstemp (*tmpname)) < 0)
    {
      saved_errno = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "failed to create temporary file %s: %s",
                   *tmpname, g_strerror (saved_errno));
      g_free (*tmpname);

      return NULL;
    }

  if ((saved_errno = posix_fallocate (*fd, 0, bytes)))
    {
      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "failed to allocate %d bytes for temporary file %s: %s",
                   bytes, *tmpname, g_strerror (saved_errno));
      unlink (*tmpname); 
      g_free (*tmpname);
      close (*fd);

      return NULL;
    }

  if ((contents = mmap (NULL, bytes, PROT_READ | PROT_WRITE,
                        MAP_SHARED, *fd, 0)) == MAP_FAILED)
    {
      saved_errno = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "failed to memory-map temporary file %s: %s",
                   *tmpname, g_strerror (saved_errno));
      unlink (*tmpname); 
      g_free (*tmpname);
      close (*fd);

      return NULL;
    }

  /* surely nobody's mmap is really this evil... */
  g_assert (contents != NULL);

  return contents;
}

static gboolean
dconf_writer_rename_temp (gchar        *tmpname,
                          const gchar  *filename,
                          GError      **error)
{
  if (rename (tmpname, filename))
    {
      gint saved_error = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_error),
                   "failed to rename temporary file %s to %s: %s",
                   tmpname, filename, g_strerror (saved_error));
      g_free (tmpname);

      return FALSE;
    }

  g_free (tmpname);

  return TRUE;
}

gboolean
dconf_writer_create (DConfWriter  *writer,
                     GError      **error)
{
  struct superblock *previous_super = NULL;
  GTree *previous_contents = NULL;
  gsize previous_size;
  gint blocks, bytes;
  gpointer contents;
  gchar *tmpname;

  if (!dconf_writer_create_directory (writer->filename, error))
    return FALSE;

  /* if there was a database already open... */
  if (writer->data.super != NULL)
    {
      /* store the information we need */
      previous_contents = dconf_writer_flatten (writer);
      previous_super = writer->data.super;
      previous_size = (gchar *) writer->end - (gchar *) previous_super;

      /* clear/reset the rest */
      g_ptr_array_foreach (writer->extras, (GFunc) g_free, NULL);
      g_ptr_array_set_size (writer->extras, 0);
      writer->changed_pointer = NULL;
      writer->changed_value = 0;
      writer->data.super = NULL;
      writer->end = NULL;
      close (writer->fd);
      writer->fd = -1;

      /* treat an empty db as if there were no db at all */
      if (g_tree_nnodes (previous_contents) == 0)
        {
          g_tree_unref (previous_contents);
          previous_contents = NULL;
        }
      else
        blocks = dconf_writer_measure_tree (previous_contents);
    }

  if (previous_contents == NULL)
    blocks = sizeof (struct superblock) / 8;

  bytes = blocks * sizeof (struct chunk_header);
  bytes += 100;

  if ((contents = dconf_writer_create_temp_file (writer->filename,
                                                 &writer->fd, bytes,
                                                 &tmpname, error)) == NULL)
    {
      munmap (previous_super, previous_size);
      return FALSE;
    }

  writer->data.super = contents;
  writer->end = ((gchar *) contents) + bytes;
  writer->data.super->signature[0] = DCONF_SIGNATURE_0;
  writer->data.super->signature[1] = DCONF_SIGNATURE_1;
  writer->data.super->next = sizeof (struct superblock) /
                               sizeof (struct chunk_header);
  writer->data.super->root_index = 0;

  if (previous_contents != NULL)
    {
      const gchar **names;
      GVariant **values;
      gint num;

      dconf_writer_unzip_tree (previous_contents, &names, &values, &num);
      dconf_writer_merge (writer, "", names, values, num);
      g_tree_unref (previous_contents);
      g_free (values);
      g_free (names);

      g_assert (writer->extras->len == 0);
      dconf_writer_sync (writer, NULL);
    }

  if (!dconf_writer_rename_temp (tmpname, writer->filename, error))
    {
      munmap (previous_super, previous_size);
      munmap (contents, bytes);
      return FALSE;
    }

  if (previous_super != NULL)
    {
      previous_super->flags |= DCONF_FLAG_STALE;
      munmap (previous_super, previous_size);
    }

  if G_UNLIKELY (writer->data.super->next != blocks)
    g_critical ("New file should have been be %d blocks, but it was %d",
                blocks, writer->data.super->next);

  return TRUE;
}

static gboolean
dconf_writer_open (DConfWriter  *writer,
                   GError      **error)
{
  struct superblock *super;
  struct stat buf;

  if ((writer->fd = open (writer->filename, O_RDWR)) < 0)
    {
      gint saved_errno = errno;
 
      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "failed to open existing dconf database %s: %s",
                   writer->filename, g_strerror (saved_errno));

      return FALSE;
    }

  if (fstat (writer->fd, &buf))
    {
      gint saved_errno = errno;
 
      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "failed to fstat existing dconf database %s: %s",
                   writer->filename, g_strerror (saved_errno));
      close (writer->fd);

      return FALSE;
    }

  if (buf.st_size < sizeof (struct superblock))
    {
      g_set_error (error, G_FILE_ERROR, G_FILE_ERROR_FAILED,
                   "existing dconf database file %s is too small "
                   "(%ld < 32 bytes)", writer->filename, buf.st_size);
      close (writer->fd);

      return FALSE;
    }

  if (buf.st_size % sizeof (struct chunk_header))
    {
      g_set_error (error, G_FILE_ERROR, G_FILE_ERROR_FAILED,
                   "existing dconf database file %s must be a multiple of "
                   "8 bytes in size (is %ld bytes)",
                   writer->filename, buf.st_size);
      close (writer->fd);

      return FALSE;
     }

  if ((super = mmap (NULL, buf.st_size,
                     PROT_READ | PROT_WRITE,
                     MAP_SHARED, writer->fd, 0)) == MAP_FAILED)
    {
      gint saved_errno = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "failed to memory-map existing dconf database file %s: %s",
                   writer->filename, g_strerror (saved_errno));
      close (writer->fd);

      return FALSE;
    }

  if (super->signature[0] != DCONF_SIGNATURE_0 ||
      super->signature[1] != DCONF_SIGNATURE_1)
    {
      g_set_error (error, G_FILE_ERROR, G_FILE_ERROR_FAILED,
                   "existing dconf database file %s has invalid signature",
                   writer->filename);

      munmap (super, buf.st_size);

      return FALSE;
    }

  writer->data.super = super;
  writer->end = writer->data.blocks + buf.st_size / 8;

  return TRUE;
}

DConfWriter *
dconf_writer_new (const gchar  *filename,
                  GError      **error)
{
  GError *my_error = NULL;
  DConfWriter *writer;

  writer = g_slice_new (DConfWriter);
  writer->filename = g_strdup (filename);
  writer->extras = g_ptr_array_new ();

  writer->changed_pointer = NULL;
  writer->changed_value = 0;
  writer->data.super = NULL;
  writer->end = NULL;

  if (dconf_writer_open (writer, &my_error))
    return writer;

  if (my_error->domain != G_FILE_ERROR &&
      my_error->code != G_FILE_ERROR_NOENT)
    {
      g_propagate_error (error, my_error);

      g_free (writer->filename);
      g_slice_free (DConfWriter, writer);

      return FALSE;
    }

  g_clear_error (&my_error);

  if (!dconf_writer_create (writer, error))
    {
      g_free (writer->filename);
      g_slice_free (DConfWriter, writer);

      return NULL;
    }

  return writer;
}

gboolean
dconf_writer_sync (DConfWriter  *writer,
                   GError      **error)
{
  if (writer->extras->len > 0)
    return dconf_writer_create (writer, error);

  fdatasync (writer->fd);

  if (writer->changed_pointer != NULL)
    {
      *writer->changed_pointer = writer->changed_value;
      writer->changed_pointer = NULL;
      writer->changed_value = 0;

      fdatasync (writer->fd);
   
   }

  return TRUE;
}
