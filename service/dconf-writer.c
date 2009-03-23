#include "dconf-writer.h"
#include <glib/gvariant-loadstore.h>

#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>


#include <common/dconf-format.h>
#include <glib/gvariant.h>
#include <string.h>


struct OPAQUE_TYPE__DConfWriter
{
  gchar *filename;
  struct superblock *super;
  struct block_header *blocks;
  guint32 n_blocks;
};
  
static gboolean
dconf_writer_allocate (DConfWriter *writer,
                       gsize        size,
                       gpointer    *pointer,
                       guint32     *index)
{
  *index = writer->super->next;

  if (*index + 1 + (size + 7) / 8 > writer->n_blocks)
    return FALSE;

  writer->blocks[*index].size = size; 
  *pointer = &writer->blocks[*index + 1];

  writer->super->next += 1 + (size + 7) / 8;

  return TRUE;
}

static gboolean
dconf_writer_write_value (DConfWriter *writer,
                          GVariant    *value,
                          guint32     *index)
{
  gconstpointer data;
  gpointer pointer;
  GVariant *box;
  gsize size;

  box = g_variant_new_variant (value);
  size = g_variant_get_size (box);
  data = g_variant_get_data (box);

  if (!dconf_writer_allocate (writer, size, &pointer, index))
    return FALSE;

  memcpy (pointer, data, size);

  g_variant_unref (box);

  return TRUE;
}

static volatile void *
dconf_writer_get_block (DConfWriter *writer,
                        guint32      index,
                        guint32     *size)
{
  *size = writer->blocks[index].size;

  return &writer->blocks[index + 1];
}

static volatile struct dir_entry *
dconf_writer_get_dir (DConfWriter *writer,
                      guint32      index,
                      gint        *length)
{
  volatile struct dir_entry *entries;
  guint32 size;

  if (index == 0)
    {
      *length = 0;
      return NULL;
    }

  entries = dconf_writer_get_block (writer, index, &size);
  g_assert_cmpint (size % sizeof (struct dir_entry), ==, 0);

  *length = size / sizeof (struct dir_entry);

  return entries;
}

static gint
dconf_writer_check_name (DConfWriter               *writer,
                         volatile struct dir_entry *entry,
                         const gchar               *name,
                         gsize                      name_length)
{
  gint length;
  gint cmp;

  length = MIN (name_length, entry->namelen);

  cmp = memcmp ((gpointer) entry->name.direct, name, length);

  if (!cmp)
    cmp = entry->namelen - name_length;

  return cmp;
}

static gboolean
dconf_writer_set_index (DConfWriter *writer,
                        const gchar *key,
                        GVariant    *value,
                        guint32     *index)
{
  volatile struct dir_entry *old_entries;
  gint n_old_entries;
  gboolean is_dir = FALSE;
  gint insert_point;
  const gchar *end;
  gboolean in_old = FALSE;
  gint length;

  end = key;
  while (*end)
    {
      if (*end == '/')
        {
          is_dir = TRUE;
          end++;

          break;
        }

      end++;
    }

  length = end - key;

  old_entries = dconf_writer_get_dir (writer, *index,
                                      &n_old_entries);
  insert_point = 0;

  while (insert_point < n_old_entries)
    {
      int cmp;
      
      cmp = dconf_writer_check_name (writer,
                                     &old_entries[insert_point],
                                     key, length);

      if (cmp < 0)
        {
          insert_point++;
          continue;
        }

      else
        {
          in_old = (cmp == 0);
          break;
        }
    }

  if (in_old)
    {
      guint32 child_index;

      /* it needs to have the correct type */
      /* don't deal with type hcanges yet... XXX */
      if (is_dir)
        g_assert_cmpint (old_entries[insert_point].type, ==, '/');
      else
        g_assert_cmpint (old_entries[insert_point].type, ==, 'v');

      /* replace */
      child_index = old_entries[insert_point].data.index;

      if (is_dir)
        {
          if (!dconf_writer_set_index (writer, end, value, &child_index))
            return FALSE;
        }
      else
        {
          if (!dconf_writer_write_value (writer, value, &child_index))
            return FALSE;
        }

      old_entries[insert_point].data.index = child_index;
    }

  else
    {
      struct dir_entry *new_entries;
      guint32 child_index = 0;

      {
        gpointer pointer;
        gsize bytes;
       
        bytes = sizeof (struct dir_entry) * (n_old_entries + 1);

        if (!dconf_writer_allocate (writer, bytes, &pointer, index))
          return FALSE;

        new_entries = pointer;
      }

      memcpy ((gpointer) new_entries, (gpointer) old_entries,
              insert_point * sizeof (struct dir_entry));

      memcpy ((gpointer) (new_entries + insert_point + 1),
              (gpointer) (old_entries + insert_point),
              (n_old_entries - insert_point) * sizeof (struct dir_entry));

      new_entries[insert_point].namelen = length;
      memcpy (new_entries[insert_point].name.direct, key, length);
      new_entries[insert_point].locked = FALSE;

      if (is_dir)
        {
          new_entries[insert_point].type = '/';
          if (!dconf_writer_set_index (writer, end, value, &child_index))
            return FALSE;
        }
      else
        {
          new_entries[insert_point].type = 'v';
          if (!dconf_writer_write_value (writer, value, &child_index))
            return FALSE;
        }

      new_entries[insert_point].data.index = child_index;
    }

  return TRUE;
}

static gboolean
dconf_writer_open (DConfWriter *writer)
{
  gpointer contents;
  struct stat buf;
  gint fd;

  fd = open (writer->filename, O_RDWR);

  if (fd < 0)
    return FALSE;

  if (fstat (fd, &buf))
    {
      g_assert_not_reached ();
      close (fd);

      return FALSE;
    }

  g_assert (buf.st_size % 4096 == 0);
  writer->n_blocks = buf.st_size / 8;

  contents = mmap (NULL, buf.st_size,
                   PROT_READ | PROT_WRITE,
                   MAP_SHARED, fd, 0);

  writer->super = contents;
  writer->blocks = contents;

  return TRUE;
}

static gboolean
dconf_writer_invalid_dir (DConfWriter *writer,
                          guint32     *index)
{
  struct dir_entry *entry;
  gpointer pointer;

  if (!dconf_writer_allocate (writer, sizeof (struct dir_entry),
                              &pointer, index))
    return FALSE;

  entry = pointer;

  entry->type = 'b';
  entry->namelen = 8;
  entry->locked = FALSE;
  strcpy (entry->name.direct, ".invalid");
  entry->data.direct = 0;

  return TRUE;
}

static gboolean
dconf_writer_copy_block (DConfWriter *writer,
                         DConfWriter *src,
                         guint32      src_index,
                         guint32     *index)
{
  static volatile void *old_pointer;
  gpointer pointer;
  gsize size;

  old_pointer = dconf_writer_get_block (src, src_index, &size);

  if (!dconf_writer_allocate (writer, size, &pointer, index))
    return FALSE;

  memcpy (pointer, (gconstpointer) old_pointer, size);

  return TRUE;
}

static gboolean
dconf_writer_copy_directory (DConfWriter *writer,
                             DConfWriter *src,
                             guint32      src_index,
                             guint32     *index)
{
  volatile struct dir_entry *old_entries;
  struct dir_entry *entries;
  gpointer pointer;
  gint length;
  gint i;

  old_entries = dconf_writer_get_dir (src, src_index, &length);

  if (old_entries == NULL)
    return dconf_writer_invalid_dir (writer, index);

  if (!dconf_writer_allocate (writer,
                              length * sizeof (struct dir_entry),
                              &pointer, index))
    return FALSE;

  entries = pointer;

  for (i = 0; i < length; i++)
    {
      entries[i] = old_entries[i];

      if (entries[i].type == '/')
        {
          if (!dconf_writer_copy_directory (writer, src,
                                            entries[i].data.index,
                                            &entries[i].data.index))
            return FALSE;
        }
      else if (entries[i].type == 'v')
        {
          if (!dconf_writer_copy_block (writer, src,
                                        entries[i].data.index,
                                        &entries[i].data.index))
            return FALSE;
        }
    }

  return TRUE;
}

static gboolean
dconf_writer_create (DConfWriter *writer)
{
  /* the sun came up
   * shot through the blinds
   *
   * today was the day
   * and i was already behind
   */
  gpointer contents;
  int fd;

  g_assert (writer->super == NULL);

  /* XXX flink() plz */
  fd = open (writer->filename, O_RDWR | O_CREAT, 0666);
  posix_fallocate (fd, 0, 4096);

  writer->n_blocks = 4096 / 8;
  contents = mmap (NULL, 4096,
                   PROT_READ | PROT_WRITE,
                   MAP_SHARED, fd, 0);

  writer->super = contents;
  writer->blocks = contents;
  writer->super->signature[0] = DCONF_SIGNATURE_0;
  writer->super->signature[1] = DCONF_SIGNATURE_1;
  writer->super->next = sizeof (struct superblock) / 8;
  writer->super->root_index = 0;

  return TRUE;
}

gboolean
dconf_writer_set (DConfWriter *writer,
                  const gchar *key,
                  GVariant    *value)
{
  guint32 root_index;

  root_index = writer->super->root_index;
  
  if (!dconf_writer_set_index (writer, key + 1, value, &root_index))
    {
      DConfWriter *new;

      new = g_slice_new (DConfWriter);
      new->filename = writer->filename;
      new->super = NULL;
      // not quite right.. need to copy -then- rename
      dconf_writer_create (new);
      if (!dconf_writer_copy_directory (new, writer, root_index, &root_index))
        g_assert_not_reached ();
      *writer = *new; // leak internals.  fix it.
      g_slice_free (DConfWriter, new);
    }

  writer->super->root_index = root_index;

  return TRUE;
}

DConfWriter *
dconf_writer_new (const gchar *filename)
{
  DConfWriter *writer;

  writer = g_slice_new (DConfWriter);
  writer->filename = g_strdup (filename);
  writer->super = NULL;

  if (dconf_writer_open (writer))
    return writer;

  if (!dconf_writer_create (writer))
    g_assert_not_reached ();

  return writer;
}
