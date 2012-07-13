#ifndef __dconf_mock_h__
#define __dconf_mock_h__

#include "../gvdb/gvdb-reader.h"

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

#endif
