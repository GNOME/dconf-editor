#include "dconf-core.h"

#include "dconf-reader.h"
#include "dconf-base.h"

#include <string.h>
#include <glib.h>

#include "dconf-config.h"
#include "dconf-dbus.h"

static GSList *dconf_mounts;

static void
dconf_setup_mounts (void)
{
  GSList *node;

  dconf_mounts = dconf_config_read ();

  for (node = dconf_mounts; node; node = node->next)
    {
      DConfMount *mount = node->data;
      gint i;

      for (i = 0; i < mount->n_dbs; i++)
        if (mount->dbs[i]->bus == NULL)
          mount->dbs[i]->bus = dconf_dbus_new (mount->dbs[i]->bus_name, NULL);
    }
}

static DConfMount *
dconf_demux_path (const gchar **path,
                  gboolean      rel)
{
  GSList *node;

  if G_UNLIKELY (dconf_mounts == NULL)
    dconf_setup_mounts ();

  for (node = dconf_mounts; node; node = node->next)
    {
      DConfMount *mount = node->data;

      if (g_str_has_prefix (*path, mount->prefix))
        {
          if (rel)
            *path += strlen (mount->prefix);
          return mount;
        }
    }

  return NULL;
}

GVariant *
dconf_get (const gchar *key)
{
  GVariant *value = NULL;
  DConfMount *mount;

  mount = dconf_demux_path (&key, TRUE);

  if (mount)
    {
      gboolean locked = FALSE;
      gint i;

      for (i = mount->n_dbs; !locked && i >= 0; i--)
        dconf_reader_get (mount->dbs[i]->filename,
                          &mount->dbs[i]->reader,
                          key, &value, &locked);
    }

  return value;
}

/*
gchar **
dconf_list (const gchar *path,
            gint        *length)
{
  gchar **list;
  GTree *tree;

  g_print ("asking for '%s'\n", path);

  if (strcmp (path, "/") == 0)
    {
      if (length)
        *length = 3;

      return g_strsplit ("default/ user/ system/", " ", 3);
    }

  tree = g_tree_new_full ((GCompareDataFunc) strcmp, NULL, NULL, NULL);

  if (g_str_has_prefix (path, "/user/"))
    {
      gboolean locked = FALSE;

      dconf_reader_list (".d", &default_db, path + 6, tree, &locked);

      if (!locked)
        dconf_reader_list (".u", &user_db, path + 6, tree, &locked);
    }

  else if (g_str_has_prefix (path, "/system/"))
    dconf_reader_list (".s", &system_db, path + 8, tree, NULL);

  else if (g_str_has_prefix (path, "/default/"))
    dconf_reader_list (".d", &default_db, path + 8, tree, NULL);

  list = g_new (gchar *, g_tree_nnodes (tree) + 1);

  {
    gchar **ptr = list;
    g_tree_foreach (tree, append_to_array, &ptr);
    *ptr = NULL;
  }

  if (length)
    *length = g_tree_nnodes (tree);

  g_tree_destroy (tree);

  return list;
}
*/

void
dconf_watch (const gchar    *match,
             DConfWatchFunc  callback,
             gpointer        user_data)
{
  if G_UNLIKELY (dconf_mounts == NULL)
    dconf_setup_mounts ();

  if (strcmp (match, "/") == 0)
    {
      GSList *node;

      for (node = dconf_mounts; node; node = node->next)
        {
          DConfMount *mount = node->data;
          gint i;

          for (i = 0; i < mount->n_dbs; i++)
            dconf_dbus_watch (mount->dbs[i]->bus, mount->prefix,
                              callback, user_data);
        }
    }
  else
    {
      DConfMount *mount;

      mount = dconf_demux_path (&match, FALSE);

      if (mount)
        {
          gint i;

          for (i = 0; i < mount->n_dbs; i++)
            dconf_dbus_watch (mount->dbs[i]->bus, match,
                              callback, user_data);
        }
    }
}


void
dconf_unwatch (const gchar    *match,
               DConfWatchFunc  callback,
               gpointer        user_data)
{
  if G_UNLIKELY (dconf_mounts == NULL)
    dconf_setup_mounts ();

  if (strcmp (match, "/") == 0)
    {
      GSList *node;

      for (node = dconf_mounts; node; node = node->next)
        {
          DConfMount *mount = node->data;
          gint i;

          for (i = 0; i < mount->n_dbs; i++)
            dconf_dbus_unwatch (mount->dbs[i]->bus, mount->prefix,
                                callback, user_data);
        }
    }
  else
    {
      DConfMount *mount;

      mount = dconf_demux_path (&match, FALSE);

      if (mount)
        {
          gint i;

          for (i = 0; i < mount->n_dbs; i++)
            dconf_dbus_unwatch (mount->dbs[i]->bus, match,
                                callback, user_data);
        }
    }
}

gboolean
dconf_merge_finish (DConfAsyncResult  *result,
                    guint32           *sequence,
                    GError           **error)
{
  return dconf_dbus_merge_finish ((DConfDBusAsyncResult *) result,
                                  sequence, error);
}

void
dconf_merge_tree_async (const gchar             *prefix,
                        GTree                   *values,
                        DConfAsyncReadyCallback  callback,
                        gpointer                 user_data)
{
  DConfMount *mount;

  mount = dconf_demux_path (&prefix, TRUE);
  g_assert (mount);

  dconf_dbus_merge_tree_async (mount->dbs[0]->bus, prefix, values,
                               (DConfDBusAsyncReadyCallback) callback,
                               user_data);
}
