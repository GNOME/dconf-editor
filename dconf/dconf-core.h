#include <glib.h>
typedef void (*DConfWatchFunc) (const gchar *prefix, const gchar * const *items, guint32 sequence, gpointer user_data);
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

typedef struct OPAQUE_TYPE__DConfAsyncResult DConfAsyncResult;
gboolean dconf_merge_finish (DConfAsyncResult *result,
                             guint32 *sequence,
                             GError **error);
typedef void (*DConfAsyncReadyCallback) (DConfAsyncResult *, gpointer user_data);
void dconf_merge_tree_async (const gchar *prefix,
                             GTree *values,
                             DConfAsyncReadyCallback callback,
                             gpointer user_data);
