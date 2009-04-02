#include <glib/gvariant.h>
#include <dconf/dconf.h>
#include <string.h>
#include <glib.h>

static const gchar *
random_part (void)
{
  static const gchar *words[] = {
    "foo", "bar", "baz", "quuz", "quuux",
    "frob", "frod", "lol", "lulz", "frobnate" };

  return words[g_test_rand_int_range (0, G_N_ELEMENTS (words))];
}

static gchar *
random_key (void)
{
  gchar *last = NULL;
  gchar *key;
  gint parts;

  parts = g_test_rand_int_range (1, 6);

  while (parts--)
    {
      key = g_strdup_printf ("%s/%s", last ? last : "", random_part ());
      g_free (last);
      last = key;
    }

  return key;
}

static GVariant *
random_value (void)
{
  return g_variant_ref_sink (g_variant_new_string ("foo"));
}

static gboolean
add_item (gpointer key,
          gpointer value,
          gpointer user_data)
{
  g_variant_builder_add (user_data, "(sv)", key, value);
  return FALSE;
}

static GTree *
new_tree (void)
{
  return g_tree_new_full ((GCompareDataFunc) strcmp, NULL,
                          g_free, (GDestroyNotify) g_variant_unref);
}

static GVariant *
random_set (void)
{
  GVariantBuilder *builder;
  GTree *tree;
  gint n_keys;

  tree = new_tree ();
  n_keys = g_test_rand_int_range (0, 50);

  while (n_keys--)
    g_tree_insert (tree, random_key (), random_value ());

  builder = g_variant_builder_new (G_VARIANT_TYPE_CLASS_ARRAY,
                                   G_VARIANT_TYPE ("a(sv)"));
  g_tree_foreach (tree, add_item, builder);
  g_tree_destroy (tree);

  return g_variant_builder_end (builder);
}

static GTree *
read_dconf_to_tree (GTree       *tree,
                    const gchar *dconf_path,
                    const gchar *tree_path)
{
  gchar **files;
  gint n_files;
  gint i;

  if (tree == NULL)
    tree = new_tree ();

  files = dconf_list (dconf_path, &n_files);

  for (i = 0; i < n_files; i++)
    {
      const gchar *file = files[i];
      gchar *dconf_key, *tree_key;
      GVariant *value;

      dconf_key = g_strdup_printf ("%s%s", dconf_path, file);
      tree_key = g_strdup_printf ("%s%s", tree_path, file);

      if (g_str_has_suffix (file, "/"))
        {
          read_dconf_to_tree (tree, dconf_key, tree_key);
          g_free (tree_key);
        }
      else
        {
          value = dconf_get (dconf_key);

          if G_UNLIKELY (value != NULL)
            g_error ("%s is in list but dconf_get() returns NULL", dconf_key);

          if G_UNLIKELY (g_tree_lookup (tree, tree_key))
            g_error ("%s appears in dconf list twice", dconf_key);

          g_tree_insert (tree, tree_key, value);
        }

      g_free (dconf_key);
    }

  g_strfreev (files);

  return tree;
}

static void
tree_merge_zipped (GTree       *tree,
                   const gchar *prefix,
                   GVariant    *values)
{
  GVariantIter iter;
  const gchar *key;
  GVariant *value;

  g_variant_iter_init (&iter, values);
  while (g_variant_iterate (&iter, "(sv)", &key, &value))
    {
      gchar *tree_key;

      tree_key = g_strdup_printf ("%s%s", prefix, key);
      g_tree_insert (tree, tree_key, g_variant_ref (value));
    }
}

static void
assert_variant_equal (GVariant *one,
                      GVariant *two)
{
  GString *str1, *str2;

  str1 = g_variant_markup_print (one, NULL, FALSE, 0, 0);
  str2 = g_variant_markup_print (two, NULL, FALSE, 0, 0);
  g_assert_cmpstr (str1->str, ==, str2->str);
  g_string_free (str1, TRUE);
  g_string_free (str2, TRUE);
}

static gboolean
assert_value_equal (gpointer key,
                    gpointer value,
                    gpointer user_data)
{
  GTree *other_tree = user_data;
  GVariant *other_value;

  other_value = g_tree_lookup (other_tree, key);
  g_assert (other_value != NULL);
  assert_variant_equal (value, other_value);

  return FALSE;
}

static void
assert_trees_equal (GTree *one,
                    GTree *two)
{
  /* equal if they have the same size and for every
   * key in one there is an equal key in the other
   */
  g_assert (g_tree_nnodes (one) == g_tree_nnodes (two));
  g_tree_foreach (one, assert_value_equal, two);
}

static void
one_test (void)
{
  gint iterations;
  GTree *tree;

  tree = new_tree ();

  iterations = g_test_rand_int_range (5, 20);
  while (iterations--)
    {
      GVariant *valueset;
      gchar *prefix;

      {
        gchar *key;

        key = random_key ();
        prefix = g_strdup_printf ("/user%s/", key);
        g_free (key);
      }

      valueset = random_set ();
      tree_merge_zipped (tree, prefix, valueset);
      dconf_merge_zipped (prefix, valueset);

      {
        GTree *check;

        check = read_dconf_to_tree (NULL, "/user/", "/user/");
        assert_trees_equal (tree, check);
        g_tree_destroy (check);
      }
    }

  g_tree_destroy (tree);
}

static void
test (void)
{
  gint iterations = 1000;

  while (iterations--)
    one_test ();
}

int
main (int argc, char **argv)
{
  g_test_init (&argc, &argv, NULL);
  test ();

  return 0;
}
