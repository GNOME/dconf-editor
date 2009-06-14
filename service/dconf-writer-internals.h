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

gboolean
dconf_writer_allocate (DConfWriter *writer,
                       gsize        size,
                       gpointer    *pointer,
                       guint32     *index);

#endif /* _dconf_writer_internals_h_ */
