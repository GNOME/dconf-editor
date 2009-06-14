#include "dconf-core.h"
#include <string.h>

static void
cb (const gchar         *prefix,
    const gchar * const *items,
    guint32              sequence,
    gpointer             user_data)
{
  g_print ("got not %s (seq %d)\n", prefix, sequence);
  while (*items)
    g_print ("  %s\n", *items++);
  g_print ("\n");
}

static void
done (DConfAsyncResult *result,
      gpointer          user_data)
{
  GError *error = NULL;
  guint32 sequence;

  if (dconf_merge_finish (result, &sequence, &error))
    {
      g_print ("got reply.  seq is %d\n", sequence);
    }
  else
    {
      g_print ("got an error: %s\n", error->message);
    }
}

int
main (void)
{
  GTree *tree;

  tree = g_tree_new ((GCompareFunc) strcmp);
  g_tree_insert (tree, "global/options", g_variant_ref_sink (g_variant_new ("i", 123)));
  g_tree_insert (tree, "global/preferences", g_variant_ref_sink (g_variant_new ("s", "hello world!")));

  dconf_watch ("/", cb, NULL);
  dconf_merge_tree_async ("/user/apps/terminal/", tree, done, NULL);
  GVariant *var = dconf_get ("/user/apps/terminal/global/preferences");

  g_assert (var != NULL);
  g_print ("%s\n", g_variant_get_string (var, NULL));

  g_main_loop_run (g_main_loop_new (NULL, FALSE));

  return 0;
}
