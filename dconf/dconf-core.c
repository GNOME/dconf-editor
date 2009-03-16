#include "dconf-core.h"

#include "dconf-reader.h"
#include "dconf-base.h"

#include <string.h>
#include <glib.h>
#include <gbus.h>

DConfReader *default_db, *user_db, *system_db;

GVariant *
dconf_get (const gchar *key)
{
  GVariant *value = NULL;
  gboolean locked = FALSE;

  g_return_val_if_fail (dconf_is_key (key), NULL);

  if (g_str_has_prefix (key, "/user/"))
    {
      dconf_reader_get (".d", &default_db, key + 6, &value, &locked);
      if (!locked)
        dconf_reader_get (".u", &user_db, key + 6, &value, &locked);
    }
  else if (g_str_has_prefix (key, "/system/"))
    {
      dconf_reader_get (".s", &system_db, key + 8, &value, &locked);
    }
  else if (g_str_has_prefix (key, "/default/"))
    {
      dconf_reader_get (".d", &default_db, key + 9, &value, &locked);
    }

  return value;
}

static gboolean
append_to_array (gpointer               key,
                 G_GNUC_UNUSED gpointer value,
                 gpointer               data)
{
  *((*(gchar ***) data)++) = (gchar *) key;

  return FALSE;
}

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


void
dconf_set (const gchar *key,
           GVariant    *value)
{
  if (g_str_has_prefix (key, "/user/"))
    g_bus_call (G_BUS_SESSION, "ca.desrt.dconf", "/user",
                "ca.desrt.dconf", "Set", NULL, "sv", "",
                key + 5, value);
}

typedef struct
{
  DConfWatchFunc callback;
  gchar *prefix;
  gpointer user_data;
} DConfWatchData;

static gboolean
dconf_change_notify (GBus              *bus,
                     const GBusMessage *message,
                     gpointer           user_data)
{
  DConfWatchData *data = user_data;
  const gchar *key;
  gchar *absolute;

  /* XXX double check signature */
  g_bus_message_get (message, "s", &key);
  absolute = g_strdup_printf ("%s%s", data->prefix, key);
  data->callback (absolute, data->user_data);
  g_free (absolute);

  return TRUE;
}

void
dconf_watch (const gchar    *match,
             DConfWatchFunc  callback,
             gpointer        user_data)
{
  if (strcmp (match, "/") == 0)
    {
      DConfWatchData *data;
      gchar *rule;

      rule = g_strdup_printf ("type='signal',"
                              "interface='ca.desrt.dconf',"
                              "member='Notify',"
                              "path='/user'");

      data = g_slice_new (DConfWatchData);
      data->callback = callback;
      data->user_data = user_data;
      data->prefix = "/user";
      g_bus_add_match (G_BUS_SESSION, rule, dconf_change_notify, data);
      g_free (rule);
    }

  if (g_str_has_prefix (match, "/user/"))
    {
      DConfWatchData *data;
      gchar *rule;

      rule = g_strdup_printf ("type='signal',"
                              "interface='ca.desrt.dconf',"
                              "member='Notify',"
                              "path='/user',"
                              "arg0path='%s'", match + 5);

      data = g_slice_new (DConfWatchData);
      data->callback = callback;
      data->user_data = user_data;
      data->prefix = "/user";
      g_bus_add_match (G_BUS_SESSION, rule, dconf_change_notify, data);
      g_free (rule);
    }
}
