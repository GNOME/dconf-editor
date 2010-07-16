#include <glib.h>

typedef struct OPAQUE_TYPE__DConfWriter DConfWriter;

const gchar *           dconf_writer_get_shm_dir                        (void);
gchar **                dconf_writer_list_existing                      (void);
void                    dconf_writer_init                               (void);
DConfWriter *           dconf_writer_new                                (const gchar          *name);
gboolean                dconf_writer_write                              (DConfWriter          *writer,
                                                                         const gchar          *name,
                                                                         GVariant             *value,
                                                                         GError              **error);
gboolean                dconf_writer_write_many                         (DConfWriter          *writer,
                                                                         const gchar          *prefix,
                                                                         const gchar * const  *keys,
                                                                         GVariant * const     *values,
                                                                         gsize n_items,
                                                                         GError              **error);
