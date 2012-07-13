#ifndef __dconf_tmpdir_h__
#define __dconf_tmpdir_h__

#include <glib.h>

gchar *dconf_test_create_tmpdir (void);
void   dconf_test_remove_tmpdir (const gchar *tmpdir);

#endif /* __dconf_tmpdir_h__ */
