#ifndef __dconf_mock_h__
#define __dconf_mock_h__

#include "../gvdb/gvdb-reader.h"
#include <gio/gio.h>

typedef GVariant *   (* DConfMockDBusSyncCallHandler)                   (GBusType             bus_type,
                                                                         const gchar         *bus_name,
                                                                         const gchar         *object_path,
                                                                         const gchar         *interface_name,
                                                                         const gchar         *method_name,
                                                                         GVariant            *parameters,
                                                                         const GVariantType  *expected_type,
                                                                         GError             **error);

extern DConfMockDBusSyncCallHandler                         dconf_mock_dbus_sync_call_handler;
extern GQueue                                               dconf_mock_dbus_outstanding_call_handles;

void                    dconf_mock_shm_reset                            (void);
gint                    dconf_mock_shm_flag                             (const gchar *name);
void                    dconf_mock_shm_assert_log                       (const gchar *expected_log);

GvdbTable *             dconf_mock_gvdb_table_new                       (void);
void                    dconf_mock_gvdb_table_insert                    (GvdbTable   *table,
                                                                         const gchar *name,
                                                                         GVariant    *value,
                                                                         GvdbTable   *subtable);
void                    dconf_mock_gvdb_table_invalidate                (GvdbTable   *table);
void                    dconf_mock_gvdb_install                         (const gchar *filename,
                                                                         GvdbTable   *table);
GvdbTable *             dconf_mock_gvdb_table_ref                       (GvdbTable   *table);

#endif
