#ifndef _dconfdatabase_h_
#define _dconfdatabase_h_

#include <glib.h>

typedef struct _DConfDatabase DConfDatabase;

G_GNUC_INTERNAL
DConfDatabase * dconf_database_get_for_backend  (gpointer       backend);

G_GNUC_INTERNAL
GVariant *      dconf_database_read             (DConfDatabase *database,
                                                 const gchar   *key);
G_GNUC_INTERNAL
gchar **        dconf_database_list             (DConfDatabase *database,
                                                 const gchar   *path,
                                                 gsize         *length);
G_GNUC_INTERNAL
void            dconf_database_write            (DConfDatabase *database,
                                                 const gchar   *path_or_key,
                                                 GVariant      *value,
                                                 gpointer       origin_tag);
G_GNUC_INTERNAL
void            dconf_database_write_tree       (DConfDatabase *database,
                                                 GTree         *tree,
                                                 gpointer       origin_tag);
G_GNUC_INTERNAL
void            dconf_database_subscribe        (DConfDatabase *database,
                                                 const gchar   *name);
G_GNUC_INTERNAL
void            dconf_database_unsubscribe      (DConfDatabase *database,
                                                 const gchar   *name);

#endif
