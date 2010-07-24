#include "dconf-state.h"

#include "dconf-shmdir.h"

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>

static void
dconf_state_init_session (DConfState *state)
{
  const gchar *config_dir = g_get_user_config_dir ();

  state->db_dir = g_build_filename (config_dir, "dconf", NULL);

  if (g_mkdir_with_parents (state->db_dir, 0700))
    {
      /* XXX remove this after a while... */
      if (errno == ENOTDIR)
        {
          gchar *tmp, *final;

          g_message ("Attempting to migrate ~/.config/dconf "
                     "to ~/.config/dconf/user");

          tmp = g_build_filename (config_dir, "dconf-user.db", NULL);

          if (rename (state->db_dir, tmp))
            g_error ("Can not rename '%s' to '%s': %s",
                     state->db_dir, tmp, g_strerror (errno));

          if (g_mkdir_with_parents (state->db_dir, 0700))
            g_error ("Can not create directory '%s': %s",
                     state->db_dir, g_strerror (errno));

          final = g_build_filename (state->db_dir, "user", NULL);

          if (rename (tmp, final))
            g_error ("Can not rename '%s' to '%s': %s",
                     tmp, final, g_strerror (errno));

          g_message ("Successful.");

          g_free (final);
          g_free (tmp);
        }
      else
        g_error ("Can not create directory '%s': %s",
                 state->db_dir, g_strerror (errno));
    }

  state->shm_dir = dconf_shmdir_from_environment ();

  if (state->shm_dir == NULL)
    {
      const gchar *tmpdir = g_get_tmp_dir ();
      gchar *shmdir;

      shmdir = g_build_filename (tmpdir, "dconf.XXXXXX", NULL);

      if ((state->shm_dir = mkdtemp (shmdir)) == NULL)
        g_error ("Can not create reasonable shm directory");
    }
}

void
dconf_state_init (DConfState *state)
{
  state->is_session = strcmp (g_get_user_name (), "dconf") != 0;
  state->main_loop = g_main_loop_new (NULL, FALSE);
  state->serial = 0;
  state->id = NULL;

  if (state->is_session)
    dconf_state_init_session (state);

  g_print ("db is %s\n", state->db_dir);
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
