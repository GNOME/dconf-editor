#include <glib.h>

gboolean dconf_rebuilder_rebuild (const gchar  *filename,
                                  const gchar  *prefix,
                                  const gchar **keys,
                                  GVariant    **values,
                                  gint          n_items,
                                  GError      **error);
