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

#ifndef _dconf_writer_private_h_
#define _dconf_writer_private_h_

#include "dconf-format.h"
#include "dconf-writer.h"

struct OPAQUE_TYPE__DConfWriter
{
  gchar *filename;
  gint fd;

  union
  {
    struct superblock *super;
    struct chunk_header *blocks;
  } data;

  volatile void *end;

  volatile guint32 *changed_pointer;
  guint32 changed_value;
  GPtrArray *extras;
};

volatile struct dir_entry *
dconf_writer_get_dir (DConfWriter *writer,
                      guint32      index,
                      gint        *n_entries);

volatile struct dir_entry *
dconf_writer_find_entry (DConfWriter                *writer,
                         volatile struct dir_entry  *entries,
                         gint                        n_entries,
                         const gchar                *name,
                         gint                        name_length);

gpointer
dconf_writer_allocate (DConfWriter *writer,
                       gsize        size,
                       guint32     *index);

const gchar *
dconf_writer_get_entry_name (DConfWriter                     *writer,
                             const volatile struct dir_entry *entry,
                             guint32                         *name_length);

void
dconf_writer_set_entry_name (DConfWriter               *writer,
                             volatile struct dir_entry *entry,
                             const gchar               *name,
                             gint                       name_length);

volatile struct dir_entry *
dconf_writer_next_entry (DConfWriter                *writer,
                         volatile struct dir_entry  *entries,
                         gint                        n_entries,
                         const gchar                *name,
                         const gchar               **next);

void
dconf_writer_set_index (DConfWriter      *writer,
                        volatile guint32 *pointer,
                        guint32           value,
                        gboolean          blind_write);

guint32
dconf_writer_get_index (DConfWriter            *writer,
                        const volatile guint32 *pointer,
                        gboolean                for_copy);

GVariant *
dconf_writer_get_entry_value (DConfWriter                     *writer,
                              const volatile struct dir_entry *entry);

GTree *
dconf_writer_flatten (DConfWriter *writer);

void
dconf_writer_unzip_tree (GTree         *tree,
                         const gchar ***names,
                         GVariant    ***values,
                         gint          *num);

gint
dconf_writer_measure_tree (GTree *tree);

#endif /* _dconf_writer_private_h_ */
