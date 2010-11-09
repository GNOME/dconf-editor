/*
 * Copyright © 2010 Codethink Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the licence, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#define _XOPEN_SOURCE 600
#include "dconf-shmdir.h"
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
dconf_engine_message_destroy (DConfEngineMessage *dcem)
{
  gint i;

  for (i = 0; dcem->parameters[i]; i++)
    g_variant_unref (dcem->parameters[i]);
  g_free (dcem->parameters);
}

void
dconf_engine_message_copy (DConfEngineMessage *orig,
                           DConfEngineMessage *copy)
{
  gint i, n;

  *copy = *orig;

  for (n = 0; orig->parameters[n]; n++);
  copy->parameters = g_new (GVariant *, n + 1);
  for (i = 0; i < n; i++)
    copy->parameters[i] = g_variant_ref (orig->parameters[i]);
  copy->parameters[i] = NULL;
}

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
      session_dir = dconf_shmdir_from_environment ();

      if (session_dir == NULL)
        {
          DConfEngineMessage dcem;
          GVariant *parameters[2];
          GVariant *result;

          dcem.bus_types = "e";
          dcem.bus_name = "ca.desrt.dconf";
          dcem.object_path = "/ca/desrt/dconf/Writer";
          dcem.interface_name = "org.freedesktop.DBus.Properties";
          dcem.method_name = "Get";
          dcem.reply_type = G_VARIANT_TYPE ("(v)");
          parameters[0] = g_variant_new ("(ss)",
                                         "ca.desrt.dconf.WriterInfo",
                                         "ShmDirectory");
          parameters[1] = NULL;
          dcem.parameters = parameters;

          result = dconf_engine_service_func (&dcem);

          g_variant_unref (parameters[0]);

          if (result != NULL)
            {
              GVariant *str;

              g_variant_get (result, "(v)", &str);

              if (g_variant_is_of_type (str, G_VARIANT_TYPE_STRING))
                session_dir = g_variant_dup_string (str, NULL);
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
  guint64     state;

  guint8     *shm;

  GvdbTable **gvdbs;
  gchar     **object_paths;
  gchar      *bus_types;
  gchar     **names;
  gint        n_dbs;
};

static void
dconf_engine_setup_user (DConfEngine *engine)
{
  /* invariant: we never have user gvdb without shm */
  g_assert ((engine->gvdbs[0] == NULL) >= (engine->shm == NULL));

  if (engine->names[0])
    {
      const gchar *session_dir = dconf_engine_get_session_dir ();

      if (session_dir)
        {
          gchar *filename;
          gint fd;

          filename = g_build_filename (session_dir,
                                       engine->names[0],
                                       NULL);
          fd = open (filename, O_RDWR | O_CREAT, 0600);
          g_free (filename);

          if (fd >= 0)
            {
              if (ftruncate (fd, 1) == 0)
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
                                       engine->names[0],
                                       NULL);
          engine->gvdbs[0] = gvdb_table_new (filename, FALSE, NULL);
          g_free (filename);
        }
    }

  g_assert ((engine->gvdbs[0] == NULL) >= (engine->shm == NULL));
}

static void
dconf_engine_refresh_user (DConfEngine *engine)
{
  g_assert ((engine->gvdbs[0] == NULL) >= (engine->shm == NULL));

  /* if we failed the first time, fail forever */
  if (engine->shm && *engine->shm == 1)
    {
      if (engine->gvdbs[0])
        {
          gvdb_table_unref (engine->gvdbs[0]);
          engine->gvdbs[0] = NULL;
        }

      munmap (engine->shm, 1);
      engine->shm = NULL;

      dconf_engine_setup_user (engine);
      engine->state++;
    }

  g_assert ((engine->gvdbs[0] == NULL) >= (engine->shm == NULL));
}

static void
dconf_engine_refresh_system (DConfEngine *engine)
{
  gint i;

  for (i = 1; i < engine->n_dbs; i++)
    {
      if (engine->gvdbs[i] && !gvdb_table_is_valid (engine->gvdbs[i]))
        {
          gvdb_table_unref (engine->gvdbs[i]);
          engine->gvdbs[i] = NULL;
        }

      if (engine->gvdbs[i] == NULL)
        {
          gchar *filename = g_build_filename ("/etc/dconf/db",
                                              engine->names[i], NULL);
          engine->gvdbs[i] = gvdb_table_new (filename, TRUE, NULL);
          if (engine->gvdbs[i] == NULL)
            g_error ("Unable to open '%s', specified in dconf profile\n",
                     filename);
          g_free (filename);
          engine->state++;
        }
    }
}

static void
dconf_engine_refresh (DConfEngine *engine)
{
  dconf_engine_refresh_system (engine);
  dconf_engine_refresh_user (engine);
}

guint64
dconf_engine_get_state (DConfEngine *engine)
{
  dconf_engine_refresh (engine);

  return engine->state;
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

  filename = g_build_filename ("/etc/dconf/profile", profile, NULL);
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
  fclose (f);

  return TRUE;
}

DConfEngine *
dconf_engine_new (const gchar *profile)
{
  DConfEngine *engine;
  gint i;

  engine = g_slice_new (DConfEngine);
  engine->shm = NULL;

  if (profile == NULL)
    profile = getenv ("DCONF_PROFILE");

  if (profile)
    {
      GError *error = NULL;

      if (!dconf_engine_load_profile (profile, &engine->names,
                                      &engine->n_dbs, &error))
        g_error ("Error loading dconf profile '%s': %s\n",
                 profile, error->message);
    }
  else
    {
      if (!dconf_engine_load_profile ("user", &engine->names,
                                      &engine->n_dbs, NULL))
        {
          engine->names = g_new (gchar *, 1);
          engine->names[0] = g_strdup ("user");
          engine->n_dbs = 1;
        }
    }

  if (strcmp (engine->names[0], "-") == 0)
    {
      g_free (engine->names[0]);
      engine->names[0] = NULL;
    }

  engine->object_paths = g_new (gchar *, engine->n_dbs);
  engine->gvdbs = g_new0 (GvdbTable *, engine->n_dbs);
  engine->bus_types = g_strdup ("eyyyyyyyyyyyyy");
  engine->state = 0;

  for (i = 0; i < engine->n_dbs; i++)
    if (engine->names[i])
        engine->object_paths[i] = g_strjoin (NULL,
                                             "/ca/desrt/dconf/Writer/",
                                             engine->names[i],
                                             NULL);
    else
      engine->object_paths[i] = NULL;

  dconf_engine_refresh_system (engine);
  dconf_engine_setup_user (engine);

  return engine;
}

void
dconf_engine_free (DConfEngine *engine)
{
  gint i;

  for (i = 0; i < engine->n_dbs; i++)
    {
      g_free (engine->object_paths[i]);
      g_free (engine->names[i]);

      if (engine->gvdbs[i])
        gvdb_table_unref (engine->gvdbs[i]);
    }

  if (engine->shm)
    {
      munmap (engine->shm, 1);
    }

  g_free (engine->object_paths);
  g_free (engine->bus_types);
  g_free (engine->names);
  g_free (engine->gvdbs);

  g_slice_free (DConfEngine, engine);
}

GVariant *
dconf_engine_read (DConfEngine  *engine,
                   const gchar  *key)
{
  GVariant *value = NULL;
  gint i;

  dconf_engine_refresh (engine);

  if (engine->gvdbs[0])
    value = gvdb_table_get_value (engine->gvdbs[0], key);

  for (i = 1; i < engine->n_dbs && value == NULL; i++)
    value = gvdb_table_get_value (engine->gvdbs[i], key);

  return value;
}

GVariant *
dconf_engine_read_default (DConfEngine  *engine,
                           const gchar  *key)
{
  GVariant *value = NULL;
  gint i;

  dconf_engine_refresh_system (engine);

  for (i = 1; i < engine->n_dbs && value == NULL; i++)
    value = gvdb_table_get_value (engine->gvdbs[i], key);

  return value;
}

GVariant *
dconf_engine_read_no_default (DConfEngine  *engine,
                              const gchar  *key)
{
  GVariant *value = NULL;

  dconf_engine_refresh_user (engine);

  if (engine->gvdbs[0])
    value = gvdb_table_get_value (engine->gvdbs[0], key);

  return value;
}

static void
dconf_engine_make_match_rule (DConfEngine        *engine,
                              DConfEngineMessage *dcem,
                              const gchar        *name,
                              const gchar        *method_name)
{
  gint i;

  dcem->bus_name = "org.freedesktop.DBus";
  dcem->object_path = "/org/freedesktop/DBus";
  dcem->interface_name = "org.freedesktop.DBus";
  dcem->method_name = method_name;

  dcem->parameters = g_new (GVariant *, engine->n_dbs + 1);
  for (i = 0; i < engine->n_dbs; i++)
    {
      gchar *rule;

      rule = g_strdup_printf ("type='signal',"
                              "interface='ca.desrt.dconf.Writer',"
                              "path='%s',"
                              "arg0path='%s'",
                              engine->object_paths[i],
                              name);
      dcem->parameters[i] = g_variant_new ("(s)", rule);
      g_variant_ref_sink (dcem->parameters[i]);
      g_free (rule);
    }
  dcem->parameters[i] = NULL;

  dcem->bus_types = engine->bus_types;
  dcem->n_messages = engine->n_dbs;
  dcem->reply_type = G_VARIANT_TYPE_UNIT;
}

void
dconf_engine_watch (DConfEngine        *engine,
                    const gchar        *name,
                    DConfEngineMessage *dcem)
{
  dconf_engine_make_match_rule (engine, dcem, name, "AddMatch");
}

void
dconf_engine_unwatch (DConfEngine        *engine,
                      const gchar        *name,
                      DConfEngineMessage *dcem)
{
  dconf_engine_make_match_rule (engine, dcem, name, "RemoveMatch");
}

gboolean
dconf_engine_is_writable (DConfEngine         *engine,
                          const gchar         *name)
{
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
                   const gchar        *method_name,
                   const gchar        *format_string,
                   ...)
{
  va_list ap;

  dcem->bus_name = "ca.desrt.dconf";
  dcem->object_path = engine->object_paths[0];
  dcem->interface_name = "ca.desrt.dconf.Writer";
  dcem->method_name = method_name;
  dcem->parameters = g_new (GVariant *, 2);
  dcem->n_messages = 1;

  va_start (ap, format_string);
  dcem->parameters[0] = g_variant_new_va (format_string, NULL, &ap);
  g_variant_ref_sink (dcem->parameters[0]);
  dcem->parameters[1] = NULL;
  va_end (ap);

  dcem->bus_types = engine->bus_types;
  dcem->reply_type = G_VARIANT_TYPE ("(s)");
}

gboolean
dconf_engine_write (DConfEngine         *engine,
                    const gchar         *name,
                    GVariant            *value,
                    DConfEngineMessage  *dcem,
                    GError             **error)
{
  dconf_engine_dcem (engine, dcem,
                     "Write", "(s@av)",
                     name, fake_maybe (value));

  return TRUE;
}

gboolean
dconf_engine_write_many (DConfEngine          *engine,
                         const gchar          *prefix,
                         const gchar * const  *keys,
                         GVariant            **values,
                         DConfEngineMessage   *dcem,
                         GError              **error)
{
  GVariantBuilder builder;
  gsize i;

  g_variant_builder_init (&builder, G_VARIANT_TYPE ("a(sav)"));

  for (i = 0; keys[i]; i++)
    g_variant_builder_add (&builder, "(s@av)",
                           keys[i], fake_maybe (values[i]));

  dconf_engine_dcem (engine, dcem, "WriteMany", "(sa(sav))", prefix, &builder);

  return TRUE;
}

void
dconf_engine_set_locked (DConfEngine        *engine,
                         const gchar        *path,
                         gboolean            locked,
                         DConfEngineMessage *dcem)
{
  dconf_engine_dcem (engine, dcem, "SetLocked", "(sb)", path, locked);
}

gchar **
dconf_engine_list (DConfEngine    *engine,
                   const gchar    *dir,
                   DConfResetList *resets,
                   gint           *length)
{
  gchar **list;

  /* not yet supported */
  g_assert (resets == NULL);

  dconf_engine_refresh (engine);

  if (engine->gvdbs[0])
    list = gvdb_table_list (engine->gvdbs[0], dir);
  else
    list = NULL;

  if (list == NULL)
    list = g_new0 (char *, 1);

  if (length)
    *length = g_strv_length (list);

  return list;
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
  if (strcmp (iface, "ca.desrt.dconf.Writer") || strcmp (method, "Notify"))
    return FALSE;

  if (!g_variant_is_of_type (body, G_VARIANT_TYPE ("(sass)")))
    return FALSE;

  if (anti_expose)
    {
      const gchar *ae;

      g_variant_get_child (body, 2, "&s", &ae);

      if (strcmp (ae, anti_expose) == 0)
        return FALSE;
    }

  g_variant_get (body, "(&s^a&ss)", path, rels, NULL);

  return TRUE;
}

gboolean
dconf_engine_interpret_reply (DConfEngineMessage  *dcem,
                              const gchar         *sender,
                              GVariant            *body,
                              gchar              **tag,
                              GError             **error)
{
  g_variant_get_child (body, 0, "s", tag);
  return TRUE;
}
