#ifndef _dconf_writer_internals_h_
#define _dconf_writer_internals_h_

#include <common/dconf-format.h>
#include "dconf-writer.h"

struct OPAQUE_TYPE__DConfWriter
{
  gchar *filename;
  struct superblock *super;
  struct block_header *blocks;
  guint32 n_blocks;
  gchar *floating;

  gpointer *extras;
  gint *extra_sizes;
  gint extras_size;
  gint n_extras;

  volatile struct dir_entry *changed_entry;
  guint32 changed_index;
};

volatile struct dir_entry *
dconf_writer_get_dir (DConfWriter *writer,
                      guint32      index,
                      gint        *n_entries);

volatile struct dir_entry *
dconf_writer_find_entry (DConfWriter               *writer,
                         volatile struct dir_entry *entries,
                         gint                       n_entries,
                         const gchar               *name,
                         gint                       name_length);

void
dconf_writer_allocate (DConfWriter *writer,
                       gsize        size,
                       gpointer    *pointer,
                       guint32     *index);

void
dconf_writer_set_entry_index (DConfWriter               *writer,
                              volatile struct dir_entry *entry,
                              guint32                    index,
                              gboolean                   blind_write);

guint32
dconf_writer_get_entry_index (DConfWriter               *writer,
                              volatile struct dir_entry *entry,
                              gboolean                   for_copy);

const gchar *
dconf_writer_get_entry_name (DConfWriter                     *writer,
                             const volatile struct dir_entry *entry,
                             guint32                         *name_length);

void
dconf_writer_set_entry_name (DConfWriter               *writer,
                             volatile struct dir_entry *entry,
                             const gchar               *name,
                             gint                       name_length);

#endif /* _dconf_writer_internals_h_ */
