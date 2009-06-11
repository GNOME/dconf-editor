#ifndef _dconf_private_types_h_
#define _dconf_private_types_h_

#include <glib.h>

typedef struct OPAQUE_TYPE__DConfReader DConfReader;
typedef struct OPAQUE_TYPE__DConfDBus   DConfDBus;

typedef struct
{
  gchar *filename;
  DConfReader *reader;

  gchar *bus_name;
  DConfDBus *bus;
} DConfDB;

typedef struct
{
  const gchar *prefix;

  DConfDB **dbs;
  gint n_dbs;
} DConfMount;

#endif /* _dconf_private_types_h_ */
