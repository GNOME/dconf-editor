
#define _XOPEN_SOURCE 600
#include "dconf-engine.h"
#include <gvdb-reader.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

static DConfEngineServiceFunc dconf_engine_service_func;

void
dconf_engine_set_service_func (DConfEngineServiceFunc func)
{
  dconf_engine_service_func = func;
}

static const gchar *
dconf_engine_get_session_dir (void)
{
  static const gchar *session_dir;
  static gsize initialised;

  if (g_once_init_enter (&initialised))
    {
      session_dir = g_strdup (getenv ("DCONF_SESSION_DIR"));

      if (session_dir == NULL)
        {
          DConfEngineMessage dcem;
          GVariant *result;

          dcem.bus_type = 'e';
          dcem.destination = "ca.desrt.dconf";
          dcem.object_path = "/ca/desrt/dconf/Writer";
          dcem.interface = "org.freedesktop.DBus.Properties";
          dcem.method = "Get";
          dcem.reply_type = G_VARIANT_TYPE ("(v)");
          dcem.body = g_variant_new ("(ss)",
                                     "ca.desrt.dconf.WriterInfo",
                                     "ShmDirectory");

          result = dconf_engine_service_func (&dcem);

          if (result != NULL)
            {
              GVariant *str;

              g_variant_get (result, "(v)", &str);

              if (g_variant_is_of_type (str, G_VARIANT_TYPE_STRING))
                session_dir = g_variant_get_string (str, NULL);
              else
                g_critical ("dconf service sent invalid reply");

              g_variant_unref (result);
              g_variant_unref (str);
            }
          else
            g_critical ("Unable to contact dconf service");
        }

      g_once_init_leave (&initialised, 1);
    }

  return session_dir;
}

struct _DConfEngine
{
  guint8 *shm;
  GvdbTable *gvdb;
  gchar *name;
  gchar *object_path;
  gint ref_count;
};

static void
dconf_engine_setup (DConfEngine *engine)
{
  /* invariant: we never have gvdb without shm */
  g_assert ((engine->gvdb == NULL) >= (engine->shm == NULL));

  if (engine->object_path)
    {
      const gchar *session_dir = dconf_engine_get_session_dir ();

      if (session_dir)
        {
          gchar *filename;
          gint fd;

          filename = g_build_filename (session_dir,
                                       engine->name,
                                       NULL);
          fd = open (filename, O_RDWR | O_CREAT, 0600);
          g_free (filename);

          if (fd >= 0)
            {
              if (posix_fallocate (fd, 0, 1) == 0)
                {
                  engine->shm = mmap (NULL, 1, PROT_READ, MAP_SHARED, fd, 0);

                  if (engine->shm == MAP_FAILED)
                    engine->shm = NULL;
                }

              close (fd);
            }
        }

      if (engine->shm)
        {
          gchar *filename;

          filename = g_build_filename (g_get_user_config_dir (),
                                       "dconf",
                                       engine->name,
                                       NULL);
          engine->gvdb = gvdb_table_new (filename, FALSE, NULL);
          g_free (filename);
        }
    }

  g_assert ((engine->gvdb == NULL) >= (engine->shm == NULL));
}

static void
dconf_engine_refresh (DConfEngine *engine)
{
  g_assert ((engine->gvdb == NULL) >= (engine->shm == NULL));

  /* if we failed the first time, fail forever */
  if (engine->shm && *engine->shm == 1)
    {
      if (engine->gvdb)
        {
          gvdb_table_unref (engine->gvdb);
          engine->gvdb = NULL;
        }

      munmap (engine->shm, 1);
      engine->shm = NULL;

      dconf_engine_setup (engine);
    }

  g_assert ((engine->gvdb == NULL) >= (engine->shm == NULL));
}


static gboolean
dconf_engine_load_profile (const gchar   *profile,
                           gchar       ***dbs,
                           gint          *n_dbs,
                           GError       **error)
{
  gchar *filename;
  gint allocated;
  char line[80];
  FILE *f;

  filename = g_build_filename ("/etc/dconf/profiles", profile, NULL);
  f = fopen (filename, "r");

  if (f == NULL)
    {
      gint saved_errno = errno;

      g_set_error (error, G_FILE_ERROR,
                   g_file_error_from_errno (saved_errno),
                   "open '%s': %s", filename, g_strerror (saved_errno));
      g_free (filename);
      return FALSE;
    }

  allocated = 4;
  *dbs = g_new (gchar *, allocated);
  *n_dbs = 0;

  /* quick and dirty is good enough for now */
  while (fgets (line, sizeof line, f))
    {
      const gchar *end;

      end = strchr (line, '\n');

      if (end == NULL)
        g_error ("long line in %s", filename);

      if (end == line)
        continue;

      if (line[0] == '#')
        continue;

      if (*n_dbs == allocated)
        {
          allocated *= 2;
          *dbs = g_renew (gchar *, *dbs, allocated);
        }

      (*dbs)[(*n_dbs)++] = g_strndup (line, end - line);
    }

  *dbs = g_renew (gchar *, *dbs, *n_dbs);
  g_free (filename);

  return TRUE;
}

DConfEngine *
dconf_engine_new (void)
{
  const gchar *profile;
  DConfEngine *engine;
  gchar **dbs;
  gint n_dbs;

  profile = getenv ("DCONF_PROFILE");

  if (profile)
    {
      GError *error = NULL;

      if (!dconf_engine_load_profile (profile, &dbs, &n_dbs, &error))
        g_error ("Error loading dconf profile '%s': %s\n",
                 profile, error->message);
    }
  else
    {
      if (!dconf_engine_load_profile ("user", &dbs, &n_dbs, NULL))
        {
          dbs = g_new (gchar *, 1);
          dbs[0] = g_strdup ("user");
          n_dbs = 1;
        }
    }

  engine = g_slice_new (DConfEngine);
  engine->ref_count = 1;
  engine->gvdb = NULL;
  engine->shm = NULL;

  if (strcmp (dbs[0], "-") != 0)
    {
      engine->name = g_strdup (dbs[0]);
      engine->object_path = g_strjoin (NULL,
                                       "/ca/desrt/dconf/Writer/",
                                       dbs[0], NULL);
    }
  else
    {
      engine->name = NULL;
      engine->object_path = NULL;
    }

  dconf_engine_setup (engine);

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
  g_slice_free (DConfEngine, engine);
}

GVariant *
dconf_engine_read (DConfEngine   *engine,
                   const gchar   *key,
                   DConfReadType  type)
{
  GVariant *value = NULL;

  if (type != DCONF_READ_RESET)
    {
      dconf_engine_refresh (engine);

      if (engine->gvdb)
        value = gvdb_table_get_value (engine->gvdb, key);
    }

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
  dcem->object_path = engine->object_path;
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
  dcem->method = "RemoveMatch";
}

gboolean
dconf_engine_is_writable (DConfEngine         *engine,
                          DConfEngineMessage  *dcem,
                          const gchar         *name,
                          GError             **error)
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
  dcem->object_path = engine->object_path;
  dcem->interface = "ca.desrt.dconf.Writer";
  dcem->reply_type = G_VARIANT_TYPE ("(t)");
  dcem->method = method;

  va_start (ap, format_string);
  dcem->body = g_variant_ref_sink (g_variant_new_va (format_string,
                                                     NULL, &ap));
  va_end (ap);
}

gboolean
dconf_engine_write (DConfEngine         *engine,
                    DConfEngineMessage  *dcem,
                    const gchar         *name,
                    GVariant            *value,
                    GError             **error)
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
                         GVariant            **values,
                         GError              **error)
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

void
dconf_engine_set_locked (DConfEngine        *engine,
                         DConfEngineMessage *dcem,
                         const gchar        *path,
                         gboolean            locked)
{
  dconf_engine_dcem (engine, dcem, "SetLocked", "(sb)", path, locked);
}

gchar **
dconf_engine_list (DConfEngine    *engine,
                   const gchar    *dir,
                   DConfResetList *resets,
                   gsize          *length)
{
  gchar **list;

  /* not yet supported */
  g_assert (resets == NULL);

  dconf_engine_refresh (engine);

  if (engine->gvdb)
    list = gvdb_table_list (engine->gvdb, dir);
  else
    list = NULL;

  if (list == NULL)
    list = g_new0 (char *, 1);

  if (length)
    *length = g_strv_length (list);

  return list;
}

static gchar *
dconf_engine_make_tag (guint        bus_type,
                       const gchar *sender,
                       guint64      seqno)
{
  return g_strdup_printf ("%c/%s/%"G_GUINT64_FORMAT, bus_type, sender, seqno);
}

gboolean
dconf_engine_decode_notify (DConfEngine   *engine,
                            const gchar   *anti_expose,
                            const gchar  **path,
                            const gchar ***rels,
                            guint          bus_type,
                            const gchar   *sender,
                            const gchar   *iface,
                            const gchar   *method,
                            GVariant      *body)
{
  guint64 seqno;
  gchar *ae;

  if (strcmp (iface, "ca.desrt.dconf.Writer") || strcmp (method, "Notify"))
    return FALSE;

  if (!g_variant_is_of_type (body, G_VARIANT_TYPE ("(tsas)")))
    return FALSE;

  g_variant_get_child (body, 0, "t", &seqno);

  if (anti_expose)
    {
      gboolean matched;

      ae = dconf_engine_make_tag (bus_type, sender, seqno);
      matched = strcmp (ae, anti_expose) == 0;
      g_free (ae);

      if (matched)
        return FALSE;
    }

  g_variant_get (body, "(t&s^a&s)", NULL, path, rels);

  return TRUE;
}

gboolean
dconf_engine_interpret_reply (DConfEngineMessage  *dcem,
                              const gchar         *sender,
                              GVariant            *body,
                              gchar              **tag,
                              GError             **error)
{
  /* typecheck and so on... */

  if (tag != NULL)
    {
      guint64 sequence;

      g_variant_get_child (body, 0, "t", &sequence);

      *tag = dconf_engine_make_tag (dcem->bus_type, sender, sequence);
    }

  return TRUE;
}
