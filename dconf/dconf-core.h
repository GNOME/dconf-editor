#include <glib/gvariant.h>
typedef void (*DConfWatchFunc) (const gchar *path, gpointer user_data);
GVariant * dconf_get (const gchar *key);
char ** dconf_list (const gchar *path,
                    gint        *length);
void dconf_set (const gchar *key,
                GVariant *value);
void dconf_watch (const gchar *match,
                  DConfWatchFunc  func,
                  gpointer        user_data);
void dconf_merge_zipped (const gchar *prefix,
                         GVariant *valueset);
