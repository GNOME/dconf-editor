
#include "dconf-engine.h"
#include <gvdb/gvdb-reader.h>

struct _DConfEngine
{
  gint ref_count;
};

DConfEngine *
dconf_engine_new (DConfEngineServiceFunc service_func)
{
  DConfEngine *engine;

  engine = g_slice_new (DConfEngine);
  engine->ref_count = 1;

  return engine;
}

DConfEngine *
dconf_engine_ref (DConfEngine *engine)
{
  g_atomic_int_inc (&engine->ref_count);

  return engine;
}

void
dconf_engine_unref (DConfEngine *engine)
{
  if (g_atomic_int_dec_and_test (&engine->ref_count))
    g_slice_free (DConfEngine, engine);
}

GVariant *
dconf_engine_read (DConfEngine        *engine,
                   const gchar        *key,
                   const GVariantType *required_type,
                   DConfEngineReadType type)
{
  GvdbTable *table;
  GVariant *value;
  gchar *filename;

  if (type == DCONF_ENGINE_READ_RESET)
    return NULL;

  filename = g_build_filename (g_get_user_config_dir (), "dconf", NULL);
  table = gvdb_table_new (filename, FALSE, NULL);
  g_free (filename);

  value = gvdb_table_get_value (table, key, NULL);

  gvdb_table_unref (table);

  return value;
}

static void
dconf_engine_make_match_rule (DConfEngine        *engine,
                              DConfEngineMessage *dcem,
                              const gchar        *name)
{
  gchar *rule;

  rule = g_strdup_printf ("interface='ca.desrt.dconf.Writer',"
                          "arg1path='%s'", name);
  dcem->bus_type = 'e';
  dcem->destination = "org.freedesktop.DBus";
  dcem->object_path = "/";
  dcem->interface = "org.freedesktop.DBus";
  dcem->body = g_variant_ref_sink (g_variant_new ("(s)", rule));
  g_free (rule);
}

void
dconf_engine_watch (DConfEngine        *engine,
                    DConfEngineMessage *dcem,
                    const gchar        *name)
{
  dconf_engine_make_match_rule (engine, dcem, name);
  dcem->method = "AddMatch";
}

void
dconf_engine_unwatch (DConfEngine        *engine,
                      DConfEngineMessage *dcem,
                      const gchar        *name)
{
  dconf_engine_make_match_rule (engine, dcem, name);
  dcem->method = "DeleteMatch";
}

gboolean
dconf_engine_is_writable (DConfEngine        *engine,
                          DConfEngineMessage *dcem,
                          const gchar        *name)
{
  dcem->bus_type = 'e';
  dcem->body = NULL;

  return TRUE;
}

static GVariant *
fake_maybe (GVariant *value)
{
  GVariantBuilder builder;

  g_variant_builder_init (&builder, G_VARIANT_TYPE ("av"));

  if (value != NULL)
    g_variant_builder_add (&builder, "v", value);

  return g_variant_builder_end (&builder);
}

static void
dconf_engine_dcem (DConfEngine        *engine,
                   DConfEngineMessage *dcem,
                   const gchar        *method,
                   const gchar        *format_string,
                   ...)
{
  va_list ap;

  dcem->bus_type = 'e';
  dcem->destination = "ca.desrt.dconf";
  dcem->object_path = "/";
  dcem->interface = "ca.desrt.dconf.Writer";
  dcem->method = method;

  va_start (ap, format_string);
  dcem->body = g_variant_ref_sink (g_variant_new_va (format_string,
                                                     NULL, &ap));
  va_end (ap);
}

gboolean
dconf_engine_write (DConfEngine        *engine,
                    DConfEngineMessage *dcem,
                    const gchar        *name,
                    GVariant           *value)
{
  dconf_engine_dcem (engine, dcem,
                     "Write", "(s@av)",
                     name, fake_maybe (value));

  return TRUE;
}

gboolean
dconf_engine_write_many (DConfEngine          *engine,
                         DConfEngineMessage   *dcem,
                         const gchar          *prefix,
                         const gchar * const  *keys,
                         GVariant            **values)
{
  GVariantBuilder builder;
  gsize i;

  g_variant_builder_init (&builder, G_VARIANT_TYPE ("a(sav)"));

  for (i = 0; keys[i]; i++)
    g_variant_builder_add (&builder, "(s@av)",
                           keys[i], fake_maybe (values[i]));

  dconf_engine_dcem (engine, dcem, "Merge", "(sa(sav))", prefix, &builder);

  return TRUE;
}
