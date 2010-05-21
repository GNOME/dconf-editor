
#include "dconf-client.h"
#include <gvdb/gvdb-reader.h>

struct _DConfClient
{
  gint ref_count;
};

DConfClient *
dconf_client_new (DConfClientServiceFunc service_func)
{
  DConfClient *client;

  client = g_slice_new (DConfClient);
  client->ref_count = 1;

  return client;
}

DConfClient *
dconf_client_ref (DConfClient *client)
{
  g_atomic_int_inc (&client->ref_count);

  return client;
}

void
dconf_client_unref (DConfClient *client)
{
  if (g_atomic_int_dec_and_test (&client->ref_count))
    g_slice_free (DConfClient, client);
}

GVariant *
dconf_client_read (DConfClient        *client,
                   const gchar        *key,
                   const GVariantType *required_type,
                   DConfClientReadType type)
{
  GvdbTable *table;
  GVariant *value;
  gchar *filename;

  if (type == DCONF_CLIENT_READ_RESET)
    return NULL;

  filename = g_build_filename (g_get_user_config_dir (), "dconf", NULL);
  table = gvdb_table_new (filename, FALSE, NULL);
  g_free (filename);

  value = gvdb_table_get_value (table, key, NULL);

  gvdb_table_unref (table);

  return value;
}

static void
dconf_client_make_match_rule (DConfClient        *client,
                              DConfClientMessage *dccm,
                              const gchar        *name)
{
  gchar *rule;

  rule = g_strdup_printf ("interface='ca.desrt.dconf.Writer',"
                          "arg1path='%s'", name);
  dccm->bus_type = 'e';
  dccm->destination = "org.freedesktop.DBus";
  dccm->object_path = "/";
  dccm->interface = "org.freedesktop.DBus";
  dccm->body = g_variant_ref_sink (g_variant_new ("(s)", rule));
  g_free (rule);
}

void
dconf_client_watch (DConfClient        *client,
                    DConfClientMessage *dccm,
                    const gchar        *name)
{
  dconf_client_make_match_rule (client, dccm, name);
  dccm->method = "AddMatch";
}

void
dconf_client_unwatch (DConfClient        *client,
                      DConfClientMessage *dccm,
                      const gchar        *name)
{
  dconf_client_make_match_rule (client, dccm, name);
  dccm->method = "RemoveMatch";
}

gboolean
dconf_client_is_writable (DConfClient        *client,
                          DConfClientMessage *dccm,
                          const gchar        *name)
{
  dccm->bus_type = 'e';
  dccm->body = NULL;

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
dconf_client_dccm (DConfClient        *client,
                   DConfClientMessage *dccm,
                   const gchar        *method,
                   const gchar        *format_string,
                   ...)
{
  va_list ap;

  dccm->bus_type = 'e';
  dccm->destination = "ca.desrt.dconf";
  dccm->object_path = "/";
  dccm->interface = "ca.desrt.dconf.Writer";
  dccm->method = method;

  va_start (ap, format_string);
  dccm->body = g_variant_ref_sink (g_variant_new_va (format_string,
                                                     NULL, &ap));
  va_end (ap);
}

gboolean
dconf_client_write (DConfClient        *client,
                    DConfClientMessage *dccm,
                    const gchar        *name,
                    GVariant           *value)
{
  dconf_client_dccm (client, dccm,
                     "Write", "(s@av)",
                     name, fake_maybe (value));

  return TRUE;
}

gboolean
dconf_client_write_many (DConfClient          *client,
                         DConfClientMessage   *dccm,
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

  dconf_client_dccm (client, dccm, "Merge", "(sa(sav))", prefix, &builder);

  return TRUE;
}
