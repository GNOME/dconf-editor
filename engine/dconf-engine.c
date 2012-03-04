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

static const gchar *
dconf_engine_get_session_dir (void)
{
  static const gchar *session_dir;
  static gsize initialised;

  if (g_once_init_enter (&initialised))
    {
      session_dir = dconf_shmdir_from_environment ();
      g_once_init_leave (&initialised, 1);
    }

  return session_dir;
}

struct _DConfEngine
{
  GMutex      lock;
  guint64     state;


  GvdbTable **gvdbs;
  GvdbTable **lock_tables;
  guint8    **shm;
  gchar     **object_paths;
  gchar      *bus_types;
  gchar     **names;
  gint        n_dbs;
};

static void
dconf_engine_setup_user (DConfEngine *engine,
                         gint         i)
{
  /* invariant: we never have user gvdb without shm */
  g_assert ((engine->gvdbs[i] == NULL) >= (engine->shm[i] == NULL));

  if (engine->names[i])
    {
      const gchar *session_dir = dconf_engine_get_session_dir ();

      if (session_dir)
        {
          gchar *filename;
          gint fd;

          filename = g_build_filename (session_dir,
                                       engine->names[i],
                                       NULL);
          fd = open (filename, O_RDWR | O_CREAT, 0600);
          g_free (filename);

          if (fd >= 0)
            {
              if (ftruncate (fd, 1) == 0)
                {
                  engine->shm[i] = mmap (NULL, 1, PROT_READ, MAP_SHARED, fd, 0);

                  if (engine->shm[i] == MAP_FAILED)
                    engine->shm[i] = NULL;
                }

              close (fd);
            }
        }

      if (engine->shm[i])
        {
          gchar *filename;

          filename = g_build_filename (g_get_user_config_dir (),
                                       "dconf",
                                       engine->names[i],
                                       NULL);
          engine->gvdbs[i] = gvdb_table_new (filename, FALSE, NULL);
          g_free (filename);
        }
    }

  g_assert ((engine->gvdbs[i] == NULL) >= (engine->shm[i] == NULL));
}

static void
dconf_engine_refresh_user (DConfEngine *engine,
                           gint         i)
{
  g_assert ((engine->gvdbs[i] == NULL) >= (engine->shm[i] == NULL));

  /* if we failed the first time, fail forever */
  if (engine->shm[i] && *engine->shm[i] == 1)
    {
      if (engine->gvdbs[i])
        {
          gvdb_table_unref (engine->gvdbs[i]);
          engine->gvdbs[i] = NULL;
        }

      munmap (engine->shm[i], 1);
      engine->shm[i] = NULL;

      dconf_engine_setup_user (engine, i);
      engine->state++;
    }

  g_assert ((engine->gvdbs[i] == NULL) >= (engine->shm[i] == NULL));
}

static void
dconf_engine_refresh_system (DConfEngine *engine,
                             gint         i)
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
      engine->lock_tables[i] = gvdb_table_get_table (engine->gvdbs[i],
                                                     ".locks");
      g_free (filename);
      engine->state++;
    }
}

static void
dconf_engine_refresh (DConfEngine *engine)
{
  gint i;

  for (i = 0; i < engine->n_dbs; i++)
    if (engine->bus_types[i] == 'e')
      dconf_engine_refresh_user (engine, i);
    else
      dconf_engine_refresh_system (engine, i);
}

static void
dconf_engine_setup (DConfEngine *engine)
{
  gint i;

  for (i = 0; i < engine->n_dbs; i++)
    if (engine->bus_types[i] == 'e')
      dconf_engine_setup_user (engine, i);
    else
      dconf_engine_refresh_system (engine, i);
}

guint64
dconf_engine_get_state (DConfEngine *engine)
{
  guint64 state;

  g_mutex_lock (&engine->lock);

  dconf_engine_refresh (engine);
  state = engine->state;

  g_mutex_unlock (&engine->lock);

  return state;
}

static gboolean
dconf_engine_load_profile (const gchar   *profile,
                           gchar        **bus_types,
                           gchar       ***names,
                           gint          *n_dbs,
                           GError       **error)
{
  gchar *filename;
  gint allocated;
  char line[80];
  FILE *f;

  /* DCONF_PROFILE starting with '/' gives an absolute path to a profile */
  if (profile[0] != '/')
    filename = g_build_filename ("/etc/dconf/profile", profile, NULL);
  else
    filename = g_strdup (profile);

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
  *bus_types = g_new (gchar, allocated);
  *names = g_new (gchar *, allocated);
  *n_dbs = 0;

  /* quick and dirty is good enough for now */
  while (fgets (line, sizeof line, f))
    {
      const gchar *end;
      const gchar *sep;

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
          *names = g_renew (gchar *, *names, allocated);
          *bus_types = g_renew (gchar, *bus_types, allocated);
        }

      sep = strchr (line, ':');

      if (sep)
        {
          /* strings MUST be 'user-db' or 'system-db'.  we do the check
           * this way here merely because it is the fastest.
           */
          (*bus_types)[*n_dbs] = (line[0] == 'u') ? 'e' : 'y';
          (*names)[*n_dbs] = g_strndup (sep + 1, end - (sep + 1));
        }
      else
        {
          /* default is for first DB to be user and rest to be system */
          (*bus_types)[*n_dbs] = (*n_dbs == 0) ? 'e' : 'y';
          (*names)[*n_dbs] = g_strndup (line, end - line);
        }

      (*n_dbs)++;
    }

  *bus_types = g_renew (gchar, *bus_types, *n_dbs);
  *names = g_renew (gchar *, *names, *n_dbs);
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
  g_mutex_init (&engine->lock);

  if (profile == NULL)
    profile = getenv ("DCONF_PROFILE");

  if (profile)
    {
      GError *error = NULL;

      if (!dconf_engine_load_profile (profile, &engine->bus_types, &engine->names, &engine->n_dbs, &error))
        g_error ("Error loading dconf profile '%s': %s\n",
                 profile, error->message);
    }
  else
    {
      if (!dconf_engine_load_profile ("user", &engine->bus_types, &engine->names, &engine->n_dbs, NULL))
        {
          engine->names = g_new (gchar *, 1);
          engine->names[0] = g_strdup ("user");
          engine->bus_types = g_strdup ("e");
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
  engine->lock_tables = g_new0 (GvdbTable *, engine->n_dbs);
  engine->shm = g_new0 (guint8 *, engine->n_dbs);
  engine->state = 0;

  for (i = 0; i < engine->n_dbs; i++)
    if (engine->names[i])
        engine->object_paths[i] = g_strjoin (NULL,
                                             "/ca/desrt/dconf/Writer/",
                                             engine->names[i],
                                             NULL);
    else
      engine->object_paths[i] = NULL;

  dconf_engine_setup (engine);

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

      if (engine->lock_tables[i])
        gvdb_table_unref (engine->lock_tables[i]);
    }

  if (engine->shm)
    {
      munmap (engine->shm, 1);
    }

  g_mutex_clear (&engine->lock);

  g_free (engine->object_paths);
  g_free (engine->bus_types);
  g_free (engine->names);
  g_free (engine->gvdbs);
  g_free (engine->lock_tables);

  g_slice_free (DConfEngine, engine);
}

static GVariant *
dconf_engine_read_internal (DConfEngine  *engine,
                            const gchar  *key,
                            gboolean      user,
                            gboolean      system)
{
  GVariant *value = NULL;
  gint lowest;
  gint limit;
  gint i;

  g_mutex_lock (&engine->lock);

  dconf_engine_refresh (engine);

  /* Bound the search space depending on the databases that we are
   * interested in.
   */
  limit = system ? engine->n_dbs : 1;
  lowest = user ? 0 : 1;

  /* We want i equal to the index of the highest database containing a
   * lock, or i == lowest if there is no lock.  For that reason, we
   * don't actually check the lowest database for a lock.  That makes
   * sense, because even if it had a lock, it would not change our
   * search policy (which would be to check the lowest one first).
   *
   * Note that we intentionally dishonour 'limit' here -- we want to
   * ensure that values in the user database are always ignored when
   * locks are present.
   */
  for (i = MAX (engine->n_dbs - 1, lowest); lowest < i; i--)
    if (engine->lock_tables[i] != NULL &&
        gvdb_table_has_value (engine->lock_tables[i], key))
      break;

  while (i < limit && value == NULL)
    {
      if (engine->gvdbs[i] != NULL)
        value = gvdb_table_get_value (engine->gvdbs[i], key);
      i++;
    }

  g_mutex_unlock (&engine->lock);

  return value;
}

GVariant *
dconf_engine_read (DConfEngine  *engine,
                   const gchar  *key)
{
  return dconf_engine_read_internal (engine, key, TRUE, TRUE);
}

GVariant *
dconf_engine_read_default (DConfEngine  *engine,
                           const gchar  *key)
{
  return dconf_engine_read_internal (engine, key, FALSE, TRUE);
}

GVariant *
dconf_engine_read_no_default (DConfEngine  *engine,
                              const gchar  *key)
{
  return dconf_engine_read_internal (engine, key, TRUE, FALSE);
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
dconf_engine_is_writable (DConfEngine *engine,
                          const gchar *name)
{
  gboolean writable = TRUE;

  /* Only check if we have more than one database */
  if (engine->n_dbs > 1)
    {
      gint i;

      g_mutex_lock (&engine->lock);

      dconf_engine_refresh (engine);

      /* Don't check for locks in the top database (i == 0). */
      for (i = engine->n_dbs - 1; 0 < i; i--)
        if (engine->lock_tables[i] != NULL &&
            gvdb_table_has_value (engine->lock_tables[i], name))
          {
            writable = FALSE;
            break;
          }

      g_mutex_unlock (&engine->lock);
    }

  return writable;
}

/* be conservative and fast:  false negatives are OK */
static gboolean
is_dbusable (GVariant *value)
{
  const gchar *type;

  type = g_variant_get_type_string (value);

  /* maybe definitely won't work.
   * variant?  too lazy to check inside...
   */
  if (strchr (type, 'v') || strchr (type, 'm'))
    return FALSE;

  /* XXX: we could also check for '{}' not inside an array...
   * but i'm not sure we want to support that anyway.
   */

  /* this will avoid any too-deeply-nested limits */
  return strlen (type) < 32;
}

static GVariant *
fake_maybe (GVariant *value)
{
  GVariantBuilder builder;

  g_variant_builder_init (&builder, G_VARIANT_TYPE ("av"));

  if (value != NULL)
    {
      if (is_dbusable (value))
        g_variant_builder_add (&builder, "v", value);

      else
        {
          GVariant *variant;
          GVariant *ay;

          variant = g_variant_new_variant (value);
          ay = g_variant_new_from_data (G_VARIANT_TYPE_BYTESTRING,
                                        g_variant_get_data (variant),
                                        g_variant_get_size (variant),
                                        TRUE,
                                        (GDestroyNotify) g_variant_unref,
                                        variant);
          g_variant_builder_add (&builder, "v", ay);

          g_variant_builder_add (&builder, "v",
                                 g_variant_new_string ("serialised GVariant"));
        }
    }

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

gchar **
dconf_engine_list (DConfEngine    *engine,
                   const gchar    *dir,
                   gint           *length)
{
  gchar **list;

  g_mutex_lock (&engine->lock);

  dconf_engine_refresh (engine);

  if (engine->gvdbs[0])
    list = gvdb_table_list (engine->gvdbs[0], dir);
  else
    list = NULL;

  if (list == NULL)
    list = g_new0 (char *, 1);

  if (length)
    *length = g_strv_length (list);

  g_mutex_unlock (&engine->lock);

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
dconf_engine_decode_writability_notify (const gchar **path,
                                        const gchar  *iface,
                                        const gchar  *method,
                                        GVariant     *body)
{
  if (strcmp (iface, "ca.desrt.dconf.Writer") ||
      strcmp (method, "WritabilityNotify"))
    return FALSE;

  if (!g_variant_is_of_type (body, G_VARIANT_TYPE ("(s)")))
    return FALSE;

  g_variant_get_child (body, 0, "&s", path);

  return TRUE;
}
