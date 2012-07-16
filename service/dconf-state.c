#include "dconf-state.h"

#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <errno.h>

static void
dconf_state_init_session (DConfState *state)
{
  const gchar *config_dir = g_get_user_config_dir ();

  state->db_dir = g_build_filename (config_dir, "dconf", NULL);

  if (g_mkdir_with_parents (state->db_dir, 0700) != 0)
    g_error ("Can not create directory '%s': %s", state->db_dir, g_strerror (errno));
}

static gboolean
dconf_state_is_blame_mode (void)
{
  gint fd;

  if (getenv ("DCONF_BLAME"))
    return TRUE;

  fd = open ("/proc/cmdline", O_RDONLY);
  if (fd != -1)
    {
      gchar buffer[1024];
      gssize s;

      s = read (fd, buffer, sizeof buffer - 1);
      close (fd);

      if (0 < s && s < sizeof buffer)
        {
          buffer[s] = '\0';
          if (strstr (buffer, "DCONF_BLAME"))
            return TRUE;
        }
    }

  return FALSE;
}

void
dconf_state_init (DConfState *state)
{
  state->blame_mode = dconf_state_is_blame_mode ();
  state->blame_info = NULL;
  state->is_session = strcmp (g_get_user_name (), "dconf") != 0;
  state->main_loop = g_main_loop_new (NULL, FALSE);
  state->serial = 0;
  state->id = NULL;

  if (state->is_session)
    dconf_state_init_session (state);
}

void
dconf_state_destroy (DConfState *state)
{
  g_main_loop_unref (state->main_loop);
}

void
dconf_state_set_id (DConfState  *state,
                    const gchar *id)
{
  g_assert (state->id == NULL);
  state->id = g_strdup (id);
}

gchar *
dconf_state_get_tag (DConfState *state)
{
  return g_strdup_printf ("%"G_GUINT64_FORMAT"%s",
                          state->serial++, state->id);
}
