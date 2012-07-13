#ifndef __dconf_state_h__
#define __dconf_state_h__

#include <glib.h>

typedef struct
{
  gboolean blame_mode;
  GString *blame_info;
  gboolean is_session;
  GMainLoop *main_loop;
  guint64 serial;
  gchar *db_dir;
  gchar *id;
} DConfState;

void                    dconf_state_init                                (DConfState  *state);
void                    dconf_state_set_id                              (DConfState  *state,
                                                                         const gchar *id);
void                    dconf_state_destroy                             (DConfState  *state);
gchar *                 dconf_state_get_tag                             (DConfState  *state);

#endif /* __dconf_state_h__ */
