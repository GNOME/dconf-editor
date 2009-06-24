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

#include <string.h>

/**
 * dconf_writer_merge_index:
 * @writer: a #DConfWriter
 * @index: in/out parameter for the index of the directory
 * @prefix: the prefix (as per the dconf_merge() call)
 * @names: the array of relative names (as per the dconf_merge() call)
 * @values: the array of values (as per the dconf_merge() call)
 * @n_items: the size of @names and @values
 * @must_copy: %TRUE if we should not attempt an in-place update
 * @returns: %TRUE on success or %FALSE if we ran out of space
 *
 * Execute an update of the database by merging one or more new values
 * into a (possibly) existing directory entry in one atomic operation.
 *
 * This is the function that does all the work in dconf.  It is very
 * complicated and this entire file is dedicated to implementing it.
 *
 * It is equivalent to performing the following set operations:
 *
 *   for (i = 0; i < n_items; i++)
 *     set (prefix + names[i], values[i]);
 *
 * such that all changes appear simultaneously.
 *
 * In the event that it is not possible to perform such a change
 * atomically then a new directory entry is allocated, the directory is
 * copied and modified and @index is updated to reflect the new
 * directory location.  The value of @index is not updated at any
 * particular time, so it must not point to the mapped file.
 *
 * If @must_copy is %TRUE then this algorithm makes no attempt to do an
 * in-place update and always copies anything that it modifies.  This is
 * required in the case of a simple update to a leaf when other updates
 * are occuring in other places of the tree so that these updates can
 * appear simultaneously.
 *
 * In the event of a failure to allocate space in the mapped file (which
 * is the only non-abort()ing way that this operation can fail) %FALSE
 * is returned.  Try again with a larger file.
 *
 * The @names array must be sorted in strcmp() order.
 *
 * @prefix must be relative to the directory at @index (ie: not start
 * with '/').  @prefix is also permitted to be the empty string.
 *
 * @n_items may not be zero.  If @n_items is 1 and the single element in
 * @names is the empty string then @prefix must be non-empty and must
 * end in a character that is not '/'.  This is the case of setting a
 * single key whose name is given entirely in @prefix.
 *
 * If @n_items is 2 or more (or if the single element in @names is not
 * the empty string) then @prefix must either be the empty string or end
 * in '/'.  Each item in @names is relative to that path.
 **/
void
dconf_writer_merge_index (DConfWriter  *writer,
                          guint32      *index,
                          const gchar  *prefix,
                          const gchar **names,
                          GVariant    **values,
                          gint          n_items,
                          gboolean      must_copy);

/*
 * If dconf_writer_merge_index() were implemented as a single function then
 * the contents of this structure would be approximately equivalent to the
 * local variables of that function.
 */
typedef struct
{
  /* if we are merging to an existing directory then old_entires points
   * at that directory.  old_length is the number of items.  old_offset
   * is the index of the item that we are currently merging.
   *
   * when old_offset == old_length then there are no more old entries.
   */
  const struct dir_entry *old_entries;
  gint                    old_length;
  gint                    old_offset;

  /* the 'prefix' that we were passed */
  const gchar *prefix;

  /* the 'names' and 'values' we were passed.
   * new_length is the size of both arrays.
   * new_offset is the index of the first item we're currently merging
   *
   * when new_offset is == new_length then there are no more new items.
   */
  const gchar **new_names;
  GVariant    **new_values;
  gint          new_length;
  gint          new_offset;

  /* this is the current name of the new items we're trying to merge.
   * this is the name that will appear directly in the dir_entry at this
   * level.
   *
   * it either points at ->prefix' or ->new_names[new_offset].
   * name_length is the length of 'name' including the trailing '/' if it
   * is a directory (then name_is_dir will be %TRUE).
   *
   * name_group_ends is what we should set the offset to after we are done
   * dealing with this name.  it will cause an increment of more than one
   * in the event that we're merging multiple items into a common
   * subdirectory.
   *
   * for example, if faced with the following new items:
   *
   *    item/1
   *    sub/item1
   *    sub/item2
   *    whatever
   *
   * then once 'name' points to new_names[1] ('sub/') (and name_length is 4)
   * then name_group_ends will point at the index of 'whatever'.  this will
   * cause both 'sub/item1' and 'sub/item2' to be handled at the same time.
   *
   * in the case that 'name' is taken from the prefix then name_group_ends
   * will be set equal to new_length.  this is because, if we have a
   * non-empty prefix, then *all* items are in a common subdirectory.
   */
  const gchar  *name;
  gint          name_length;
  gint          name_group_ends;
  gboolean      name_is_dir;
  gboolean      consuming_new;

  /* this points to the new directory that we are writing to.  during the
   * 'allocation' phase when we're doing a dry-run to calculate the size of
   * the new directory these will be NULL, 0, 0 */
  struct dir_entry *entries;
  gint              entries_length;
  gint              entries_offset;
} MergeState;

/* Some functions to perform small operations on the state */
static gboolean
merge_state_has_work (MergeState *state)
{
  return ((state->old_offset < state->old_length) ||
             (state->new_offset < state->new_length));
}

static void
merge_state_assert_done (MergeState *state)
{
  g_assert (state->entries_offset == state->entries_length);
}

static gboolean
merge_state_has_new (MergeState *state)
{
  return state->new_offset < state->new_length;
}

static gboolean
merge_state_has_old (MergeState *state)
{
  return state->old_offset < state->old_length;
}

static void
merge_state_setup_new_name (MergeState *state)
{
  const gchar *new_name;
  gint length;
  gint i;

  g_assert (state->name_is_dir == FALSE);
  g_assert (state->name == NULL);
  g_assert (state->name_length == -1);
  g_assert (state->name_group_ends == -1);

  g_assert (merge_state_has_new (state));

  if (state->prefix[0])
    new_name = state->prefix;
  else
    new_name = state->new_names[state->new_offset];

  for (length = 0; new_name[length]; length++)
    if (new_name[length] == '/')
      {
        state->name_is_dir = TRUE;
        length++;
        break;
      }

  if (new_name != state->prefix)
    {
      gint cmplen = state->name_is_dir ? length : length + 1;
      /* length + 1 for the not-directory case to check the '\0' too. */

      for (i = state->new_offset + 1; i < state->new_length; i++)
        if (memcmp (state->new_names[i], new_name, cmplen) != 0)
          break;
    }
  else
    i = state->new_length;

  state->name = new_name;
  state->name_length = length;
  state->name_group_ends = i;

  /* multiple entries with the same name? */
  g_assert (state->name_group_ends == state->new_offset + 1 ||
            state->name_is_dir);
}

static gboolean
merge_state_name_is_directory (MergeState *state)
{
  if (state->name == NULL)
    merge_state_setup_new_name (state);

  return state->name_is_dir;
}

static const gchar *
merge_state_get_new_name (MergeState *state,
                          gint       *name_length)
{
  if (state->name == NULL)
    merge_state_setup_new_name (state);

  *name_length = state->name_length;

  return state->name;
}

static const gchar
merge_state_get_new_type (MergeState *state)
{
  if (state->name == NULL)
    merge_state_setup_new_name (state);
  
  if (state->name_is_dir)
    return '/';

  return 'v';
}

static void
merge_state_next_new (MergeState *state)
{
  if (state->name == NULL)
    merge_state_setup_new_name (state);

  state->name = NULL;
  state->name_length = -1;
  state->new_offset = state->name_group_ends;
  g_assert (state->new_offset > 0);
  state->name_group_ends = -1;
  state->name_is_dir = FALSE;

  g_assert (state->new_offset <= state->new_length);
}

static void
merge_state_begin_consume_new (MergeState    *state,
                               const gchar  **rest_of_prefix,
                               const gchar ***names,
                               GVariant    ***values,
                               gint          *num_items)
{
  gint i;

  if (state->name == NULL)
    merge_state_setup_new_name (state);

  g_assert (state->consuming_new == FALSE);
  state->consuming_new = TRUE;

  if (state->name != state->prefix)
    {
      for (i = state->new_offset; i < state->name_group_ends; i++)
        state->new_names[i] += state->name_length;

      g_assert (state->prefix[0] == '\0');
      *rest_of_prefix = state->prefix;
    }
  else
    *rest_of_prefix = state->prefix + state->name_length;

  *names = &state->new_names[state->new_offset];
  *values = &state->new_values[state->new_offset];
  *num_items = state->name_group_ends - state->new_offset;
}

static void
merge_state_end_consume_new (MergeState *state)
{
  gint i;

  g_assert (state->consuming_new == TRUE);
  state->consuming_new = FALSE;

  if (state->name != state->prefix)
    for (i = state->new_offset; i < state->name_group_ends; i++)
      state->new_names[i] -= state->name_length;

  merge_state_next_new (state);
}

static const struct dir_entry *
merge_state_get_old (MergeState *state)
{
  g_assert (merge_state_has_old (state));

  return &state->old_entries[state->old_offset];
}

static void
merge_state_next_old (MergeState *state)
{
  g_assert (merge_state_has_old (state));

  state->old_offset++;
}

static const struct dir_entry *
merge_state_consume_old (MergeState *state)
{
  const struct dir_entry *item;

  item = merge_state_get_old (state);
  merge_state_next_old (state);

  return item;
}

static struct dir_entry *
merge_state_get_entry (MergeState *state)
{
  g_assert (merge_state_has_work (state));
  g_assert (state->entries_offset < state->entries_length);
  g_assert (state->entries != NULL);

  return &state->entries[state->entries_offset];
}

static void
merge_state_next_entry (MergeState *state)
{
  g_assert (merge_state_has_work (state));

  state->entries_offset++;
}

static struct dir_entry *
merge_state_consume_entry (MergeState *state)
{
  struct dir_entry *item;

  item = merge_state_get_entry (state);
  merge_state_next_entry (state);

  return item;
}

static void
dconf_writer_merge_copy_old (MergeState *state)
{
  const struct dir_entry *old;
  struct dir_entry *entry;

  old = merge_state_consume_old (state);
  entry = merge_state_consume_entry (state);
  *entry = *old;
}

static void
dconf_writer_merge_write_to_entry (DConfWriter                *writer,
                                   volatile struct dir_entry  *entry,
                                   MergeState                 *state,
                                   gboolean                    merging)
{
  const gchar *prefix;
  const gchar **names;
  GVariant **values;
  gint count;

  merge_state_begin_consume_new (state, &prefix, &names, &values, &count);

  if (merge_state_name_is_directory (state))
    {
      guint32 index;

      index = dconf_writer_get_index (writer, &entry->data.index, FALSE);

      dconf_writer_merge_index (writer, &index, prefix,
                                names, values, count,
                                merging);

      dconf_writer_set_index (writer, &entry->data.index, index, merging);
    }
  else
    {
      GVariant *variant;
      gpointer data;
      guint32 index;

      g_assert (prefix[0] == '\0');
      g_assert (count == 1);
      g_assert (names[0][0] == '\0');

      variant = g_variant_ref_sink (g_variant_new_variant (values[0]));

      data = dconf_writer_allocate (writer,
                                    g_variant_get_size (variant),
                                    &index);
      g_variant_store (variant, data);

      g_variant_unref (variant);

      dconf_writer_set_index (writer, &entry->data.index, index, merging);
    }

  merge_state_end_consume_new (state);
}

static void
dconf_writer_merge_install_new (DConfWriter *writer,
                                MergeState  *state,
                                gboolean     merge_old)
{
  struct dir_entry *entry;

  entry = merge_state_consume_entry (state);

  if (merge_old)
    {
      const struct dir_entry *old;

      old = merge_state_consume_old (state);
      *entry = *old;
    }
  else
    {
      const gchar *name;
      gint name_length;

      name = merge_state_get_new_name (state, &name_length);
      dconf_writer_set_entry_name (writer, entry, name, name_length);

      entry->data.index = 0;
      entry->locked = FALSE;
    }

  entry->type = merge_state_get_new_type (state);

  return dconf_writer_merge_write_to_entry (writer, entry, state, TRUE);
}

static gint
dconf_writer_merge_compare (DConfWriter *writer,
                            MergeState  *state)
{
  const struct dir_entry *old;
  const gchar *entry_name;
  guint32 entry_length;
  const gchar *name;
  gint name_length;
  gint result;

  old = merge_state_get_old (state);
  name = merge_state_get_new_name (state, &name_length);

  entry_name = dconf_writer_get_entry_name (writer, old, &entry_length);

  result = memcmp (entry_name, name,
                   MIN (entry_length, name_length));

  if (!result)
    result = entry_length - name_length;

  return result;
}

static void
merge_state_init (MergeState                 *state,
                  volatile struct dir_entry  *entries,
                  gint                        n_entries,
                  const gchar                *prefix,
                  const gchar               **names,
                  GVariant                  **values,
                  gint                        n_items)
{
  state->old_entries = (const struct dir_entry *) entries;
  state->old_length = n_entries;
  state->old_offset = 0;

  state->prefix = prefix;

  state->new_names = names;
  state->new_values = values;
  state->new_length = n_items;
  state->new_offset = 0;

  state->entries = NULL;
  state->entries_offset = 0;
  state->entries_length = 0;

  state->name = NULL;
  state->name_length = -1;
  state->name_group_ends = -1;
  state->name_is_dir = FALSE;
  state->consuming_new = FALSE;
}

static gboolean
merge_state_has_single_item (MergeState *state)
{
  g_assert (state->new_offset == 0);

  if (state->name == NULL)
    merge_state_setup_new_name (state);

  return state->name_group_ends == state->new_length;
}

static void
dconf_writer_merge_allocate (DConfWriter *writer,
                             MergeState  *state,
                             guint32     *index)
{
  MergeState tmp;
  gint entries;

  /* we need to calculate the directory size before we allocate it.
   * we can do this by creating a local copy of the state and seeking
   * through it as if we were performing the merge, noting how much space
   * we would need.  this is essentially a copy of the main merge
   * algorithm without writing to the new directory.
   */
  tmp = *state;

  entries = 0;

  while (merge_state_has_work (&tmp))
    {
      if (!merge_state_has_new (&tmp))
        {
          merge_state_next_old (&tmp);
          entries++;
        }
      else if (!merge_state_has_old (&tmp))
        {
          merge_state_next_new (&tmp);
          entries++;
        }
      else
        {
          int cmp = dconf_writer_merge_compare (writer, &tmp);

          if (cmp < 0)
            {
              merge_state_next_old (&tmp);
              entries++;
            }
          else
            {
              if (cmp == 0)
                merge_state_next_old (&tmp);
              merge_state_next_new (&tmp);
              entries++;
            }
        }
    }

  state->entries = dconf_writer_allocate (writer,
                                          sizeof (struct dir_entry) * entries,
                                          index);
  state->entries_length = entries;

  g_assert (state->entries != NULL);
  g_assert (state->entries_length != 0);
  g_assert (state->entries_offset == 0);
}

void
dconf_writer_merge_index (DConfWriter  *writer,
                          guint32      *index,
                          const gchar  *prefix,
                          const gchar **names,
                          GVariant    **values,
                          gint          n_items,
                          gboolean      must_copy)
{
  MergeState state;

  volatile struct dir_entry *entries;
  gint n_entries;

  if (*index)
    entries = dconf_writer_get_dir (writer, *index, &n_entries);
  else
    {
      entries = NULL;
      n_entries = 0;
    }

  merge_state_init (&state, entries, n_entries,
                    prefix, names, values, n_items);

  if (!must_copy && merge_state_has_single_item (&state))
    /* maybe we can do the update in place */
    {
      volatile struct dir_entry *entry;
      const gchar *name;
      gint namelen;

      name = merge_state_get_new_name (&state, &namelen);
      entry = dconf_writer_find_entry (writer,
                                       entries, n_entries,
                                       name, namelen);

      if (entry != NULL && entry->type == merge_state_get_new_type (&state))
        /* we can do the in-place update. */
        return dconf_writer_merge_write_to_entry (writer, entry,
                                                  &state, FALSE);
    }

  /* inplace update is not possible.  allocate a new directory. */
  dconf_writer_merge_allocate (writer, &state, index);

  /* now do the merge */
  while (merge_state_has_work (&state))
    {
      if (!merge_state_has_new (&state))
        dconf_writer_merge_copy_old (&state);

      else if (!merge_state_has_old (&state))
        dconf_writer_merge_install_new (writer, &state, FALSE);

      else
        {
          int cmp = dconf_writer_merge_compare (writer, &state);

          if (cmp < 0)
            dconf_writer_merge_copy_old (&state);

          else
            dconf_writer_merge_install_new (writer, &state, cmp == 0);
        }
    }

  merge_state_assert_done (&state);
}

gboolean
dconf_writer_merge (DConfWriter  *writer,
                    const gchar  *prefix,
                    const gchar **names,
                    GVariant    **values,
                    gint          n_items,
                    GError      **error)
{
  volatile struct superblock *super = writer->data.super;
  guint32 index;

  index = dconf_writer_get_index (writer, &super->root_index, FALSE);
  dconf_writer_merge_index (writer, &index, prefix,
                            names, values, n_items, FALSE);
  dconf_writer_set_index (writer, &super->root_index, index, FALSE);

  if (writer->changed_pointer)
    {
      *writer->changed_pointer = writer->changed_value;
      writer->changed_pointer = NULL;
    }
  else
    g_assert (n_items == 1);

  return TRUE;
}
