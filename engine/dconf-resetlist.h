#ifndef __dconf_resetlist_h__
#define __dconf_resetlist_h__

#include <glib.h>

typedef struct
{
  gpointer opaque[8];
} DConfResetList;

void                    dconf_reset_list_init                           (DConfResetList      *list,
                                                                         const gchar         *prefix,
                                                                         const gchar * const *rels,
                                                                         gsize                n_rels);
void                    dconf_reset_list_add                            (DConfResetList      *list,
                                                                         const gchar         *path);
void                    dconf_reset_list_clear                          (DConfResetList      *list);


#endif /* __dconf_resetlist_h__ */
