#include "dconfcontext.h"

static gpointer
dconf_context_thread (gpointer data)
{
  GMainContext *context = data;
  GMainLoop *loop;

  g_main_context_push_thread_default (context);
  loop = g_main_loop_new (context, FALSE);
  g_main_loop_run (loop);

  g_assert_not_reached ();
}

GMainContext *
dconf_context_get (void)
{
  static GMainContext *context;
  static gsize initialised;

  if (g_once_init_enter (&initialised))
    {
      GThread *thread;

      context = g_main_context_new ();
      thread = g_thread_create (dconf_context_thread,
                                context, FALSE, NULL);
      g_assert (thread != NULL);

      g_once_init_leave (&initialised, 1);
    }

  return context;
}
