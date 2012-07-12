#ifndef __dconf_mock_h__
#define __dconf_mock_h__

void                    dconf_mock_shm_reset                            (void);
gint                    dconf_mock_shm_flag                             (const gchar *name);
void                    dconf_mock_shm_assert_log                       (const gchar *expected_log);

typedef struct _DConfMockGvdbTable                          DConfMockGvdbTable;

DConfMockGvdbTable *    dconf_mock_gvdb_table_new                       (void);
void                    dconf_mock_gvdb_table_insert                    (DConfMockGvdbTable *table,
                                                                         const gchar        *name,
                                                                         GVariant           *value,
                                                                         DConfMockGvdbTable *subtable);
void                    dconf_mock_gvdb_install                         (const gchar        *filename,
                                                                         DConfMockGvdbTable *table);

#endif
