#include <glib.h>

typedef struct OPAQUE_TYPE__DConfWriter DConfWriter;

gboolean dconf_writer_set (DConfWriter *writer,
                           const gchar *key,
                           GVariant    *value);
DConfWriter *dconf_writer_new (const gchar *filename);

gboolean
dconf_writer_merge (DConfWriter  *writer,
                    const gchar  *prefix,
                    const gchar **names,
                    GVariant    **values,
                    gint          n_items);
