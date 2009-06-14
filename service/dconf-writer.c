#include "dconf-writer-internals.h"
#include <glib/gvariant-loadstore.h>

#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <glib/gstdio.h>
#include <errno.h>


#include <glib/gvariant.h>
#include <string.h>

gboolean
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

volatile struct dir_entry *
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

static int
dconf_writer_part_length (const gchar  *path,
                          const gchar **rest)
{
  gint length;

  for (length = 0; path[length]; length++)
    if (path[length] == '/')
      {
        length++;
        break;
      }

  if (rest != NULL)
    *rest = &path[length];

  return length;
}


static gint
dconf_writer_choose (DConfWriter *writer,
                     volatile struct dir_entry  *old_entries,
                     gint                        n_old_entries,
                     const gchar               **new_names,
                     gint                        n_new_names)
{
  if (n_old_entries == 0)
    return 1;

  else if (n_new_names == 0)
    return -1;

  else
    return dconf_writer_check_name (writer, old_entries,
                                    new_names[0], -1);
}

static gint
dconf_writer_merge_size (DConfWriter                *writer,
                         volatile struct dir_entry  *old_entries,
                         gint                        n_old_entries,
                         const gchar               **new_names,
                         gint                        n_new_names)
{
  const gchar *last_name = NULL;
  gint last_length = 0;
  gint n_entries = 0;

  while (n_old_entries || n_new_names)
    {
      const gchar *name;
      gint length;

      /* it doesn't matter who wins the tie. */
      if (dconf_writer_choose (writer, old_entries, n_old_entries,
                               new_names, n_new_names) < 0)
        {
          /* XXX long filenames */
          name = (const gchar *) old_entries->name.direct;
          length = old_entries->namelen;
          n_old_entries--;
          old_entries++;
        }
      else
        {
          name = new_names[0];
          length = dconf_writer_part_length (*new_names, NULL);
          n_new_names--;
          new_names++;
        }

      /* only count unique names */
      if (length != last_length || memcmp (name, last_name, length))
        {
          last_length = length;
          last_name = name;
          n_entries++;
        }
    }

  return n_entries;
}

static char
dconf_writer_get_type (const gchar *name,
                       gint         length,
                       GVariant    *value)
{
  if (name[length - 1] == '/')
    return '/';

  return 'v';
}


static gboolean
dconf_writer_merge_directory (DConfWriter  *writer,
                              gint          source_index,
                              const gchar **new_names,
                              GVariant    **new_values,
                              gint          new_length,
                              guint32      *index);

static gboolean
dconf_writer_write_entry (DConfWriter                *writer,
                          volatile struct dir_entry  *entry,
                          const gchar               **new_names,
                          GVariant                  **new_values,
                          gint                        new_length,
                          gchar                       type,
                          gint                        name_skip)
{
  if (type == 'v')
    {
      guint32 index;

      if (new_length != 1)
        g_warning ("Got %d keys with the same name", new_length);

      if (!dconf_writer_write_value (writer, new_values[0], &index))
        return FALSE;

      entry->data.index = index;

      return TRUE;
    }

  else if (type == '/')
    {
      guint32 index = entry->data.index;
      gboolean result;
      int i;

      for (i = 0; i < new_length; i++)
        new_names[i] += name_skip;

      result = dconf_writer_merge_directory (writer, index, new_names,
                                             new_values, new_length, &index);

      /* check before writing; we may avoid dirtying a page. */
      if (result && index != entry->data.index)
        entry->data.index = index;

      for (i = 0; i < new_length; i++)
        new_names[i] -= name_skip;

      return result;
    }

  g_assert_not_reached ();
}

static gboolean
dconf_writer_merge_directory (DConfWriter  *writer,
                              gint          source_index,
                              const gchar **new_names,
                              GVariant    **new_values,
                              gint          new_length,
                              guint32      *index)
{
  volatile struct dir_entry *old_entries;
  gint n_old_entries;
  gint n_entries;

  old_entries = dconf_writer_get_dir (writer, *index, &n_old_entries);
  n_entries = dconf_writer_merge_size (writer,
                                       old_entries, n_old_entries,
                                       new_names, new_length);

  if (n_entries == n_old_entries && new_length == 1)
    /* simple case: can probably do an in-place atomic update. */
    {
      const gchar *name;
      gint length, i;
      char type;

      length = dconf_writer_part_length (name, NULL);
      type = dconf_writer_get_type (name, length, new_values[0]);

      for (i = 0; i < n_entries; i++)
        if (!dconf_writer_check_name (writer, &old_entries[i], name, length))
          break;

      /* since n_entries == old_entries it must be in the list */
      g_assert (i < n_entries);

      if (old_entries[i].type == type)
        /* can only do in-place atomic update if it's the same type */
        return dconf_writer_write_entry (writer, &old_entries[i],
                                         new_names, new_values, 1,
                                         type, length);
    }

  /* non-simple case: need to allocate a new directory and link it. */
  {
    struct dir_entry *entries;
    gpointer pointer;
    gint i, j, k;

    if (!dconf_writer_allocate (writer,
                                sizeof (struct dir_entry) * n_entries,
                                &pointer, index))
      return FALSE;

    entries = pointer;

    i = j = k = 0;
    /* merge old_entries[i] and new_names[j] into entries[k] */
    while (i < n_old_entries || j < new_length)
      {
        gint cmp, l;
        gint length;
        char type;

        g_assert_cmpint (k, <, n_entries);

        cmp = dconf_writer_choose (writer,
                                   &old_entries[i], n_old_entries - i,
                                   new_names + j, new_length - j);
        length = dconf_writer_part_length (new_names[j], NULL);
        type = dconf_writer_get_type (new_names[j], length, new_values[j]);

        if (cmp < 0)
          /* the simple case is to copy the old entry
           * with no contribution from the new entries
           */
          {
            entries[k++] = old_entries[i++];
            continue;
          }

        /* the remaining two cases involve contribution
         * from the new entries.
         *
         * first: if we're merging (cmp == 0) then copy
         * the old entry to start.
         */
        if (cmp == 0)
          entries[k] = old_entries[i++];

        else
          {
            memcpy (entries[k].name.direct, new_names[j], length);
            entries[k].namelen = length;
            entries[k].locked = FALSE;
            entries[k].data.index = 0;
          }

        /* we can update the type field because we don't
         * have to appear atomic (since the new dir entries
         * are not linked into the parent yet).
         */
        entries[k].type = type;

        /* find out how many new entries have the same name */
        for (l = j + 1; l < new_length; l++)
          if (strncmp (new_names[j], new_names[l], length))
            break;

        /* handle them all at once */
        if (!dconf_writer_write_entry (writer, &entries[k],
                                       new_names + j, new_values + j,
                                       l - j, type, length))
          return FALSE;

        /* move past the ones we just handled */
        j = l;

        /* and onto the next entry */
        k++;
      }
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

  writer->floating = g_strdup_printf ("%s.XXXXXX", writer->filename);

  g_assert (writer->super == NULL);

  /* XXX flink() plz */
  fd = g_mkstemp (writer->floating);
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
dconf_writer_post (DConfWriter  *writer,
                   GError      **error)
{
  if (g_rename (writer->floating, writer->filename))
    {
      gint saved_error = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_error),
                   "rename '%s' to '%s': %s",
                   writer->floating, writer->filename,
                   g_strerror (saved_error));

      return FALSE;
    }

  g_free (writer->floating);
  writer->floating = NULL;

  return TRUE;
}

gboolean
dconf_writer_set (DConfWriter *writer,
                  const gchar *key,
                  GVariant    *value)
{
  guint32 root_index;

  root_index = writer->super->root_index;
  
  if (!dconf_writer_set_index (writer, key, value, &root_index))
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

  if (writer->floating)
    dconf_writer_post (writer, NULL);

  return TRUE;
}

DConfWriter *
dconf_writer_new (const gchar *filename)
{
  DConfWriter *writer;

  writer = g_slice_new (DConfWriter);
  writer->filename = g_strdup (filename);
  writer->super = NULL;
  writer->floating = NULL;

  if (dconf_writer_open (writer))
    return writer;

  if (!dconf_writer_create (writer))
    g_assert_not_reached ();

  if (!dconf_writer_post (writer, NULL))
    g_error ("could not post\n");

  return writer;
}

volatile struct dir_entry *
dconf_writer_find_entry (DConfWriter               *writer,
                         volatile struct dir_entry *entries,
                         gint                       n_entries,
                         const gchar               *name,
                         gint                       name_length)
{
  /* XXX replace with a binary search */
  gint i;

  for (i = 0; i < n_entries; i++)
    {
      g_assert (entries[i].namelen < sizeof entries[i].name.direct);
      if (entries[i].namelen == name_length &&
          !memcmp ((const gchar *) entries[i].name.direct, name, name_length))
        return &entries[i];
    }

  return NULL;
}
