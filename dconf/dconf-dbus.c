/*
 * Copyright © 2009 Codethink Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of version 3 of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#include "dconf-dbus.h"

#include <dbus/dbus.h>
#include <string.h>

typedef struct
{
  gchar *prefix;

  DConfDBusNotify callback;
  gpointer user_data;
} DConfDBusWatch;

struct OPAQUE_TYPE__DConfDBus
{
  DBusConnection *connection;
  const gchar *name;

  GSList *watches;
};

/* alexl code */
static void _g_dbus_connection_integrate_with_main (DBusConnection *);

static const gchar *
dconf_dbus_find_relative (const gchar *path)
{
  return strchr (path + 1, '/') + 1;
}

static void
dconf_dbus_notify (DConfDBus           *bus,
                   const gchar         *prefix,
                   const gchar * const *items,
                   gint                 items_length,
                   guint32              sequence)
{
  gint prefix_len;
  GSList *node;

  prefix_len = strlen (prefix);

  for (node = bus->watches; node; node = node->next)
    {
      DConfDBusWatch *watch = node->data;
      const gchar *relative_prefix;
      gint relative_len;
      gint skip;

      relative_prefix = dconf_dbus_find_relative (watch->prefix);
      skip = relative_prefix - watch->prefix;
      relative_len = strlen (relative_prefix);

      if ((memcmp (prefix, relative_prefix,
                   MIN (relative_len, prefix_len)) == 0) &&
          (relative_len == prefix_len ||
           (relative_len < prefix_len &&
            relative_prefix[relative_len - 1] == '/') ||
           (prefix_len < relative_len &&
            prefix[prefix_len - 1] == '/')))
        {
          gchar *full;

          full = g_malloc (skip + prefix_len + 1);
          memcpy (full, watch->prefix, skip);
          memcpy (full + skip, prefix, prefix_len);
          full[skip + prefix_len] = '\0';

          watch->callback (full, items, items_length,
                           sequence, watch->user_data);

          g_free (full);
        }
    }
}

static DBusHandlerResult
dconf_dbus_filter (DBusConnection *connection,
                   DBusMessage    *message,
                   void           *user_data)
{
  DBusMessageIter iter, array;
  DConfDBus *bus = user_data;
  const gchar *prefix;
  GPtrArray *items;
  guint32 seq;

  g_assert (bus->connection == connection);

  if (!dbus_message_is_signal (message, "ca.desrt.dconf", "Notify"))
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

  if (!dbus_message_has_signature (message, "sasu"))
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

  if (!dbus_message_has_path (message, bus->name))
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

  items = g_ptr_array_new ();
  dbus_message_iter_init (message, &iter);

  dbus_message_iter_get_basic (&iter, &prefix);
  dbus_message_iter_next (&iter);

  dbus_message_iter_recurse (&iter, &array);
  while (dbus_message_iter_get_arg_type (&array))
    {
      const gchar *item;

      dbus_message_iter_get_basic (&array, &item);
      g_ptr_array_add (items, (gpointer) item);
      dbus_message_iter_next (&array);
    }
  g_ptr_array_add (items, NULL);
  dbus_message_iter_next (&iter);

  dbus_message_iter_get_basic (&iter, &seq);

  dconf_dbus_notify (bus, prefix,
                     (const gchar **) items->pdata, items->len - 1,
                     seq);

  g_ptr_array_free (items, TRUE);

  return DBUS_HANDLER_RESULT_HANDLED;
}

DConfDBus *
dconf_dbus_new (const gchar  *path,
                GError      **error)
{
  DConfDBus *bus;

  bus = g_slice_new (DConfDBus);

  /* XXX yes.  this is extremely stupid.  we make no attempt to share
     dbus connections, even with ourselves.  it's easier to register
     with the mainloop this way, though.

     fix this later in order to waste less memory.
   */

  if (g_str_has_prefix (path, "system/"))
    {
      bus->connection = dbus_bus_get_private (DBUS_BUS_SYSTEM, NULL);
      bus->name = g_strdup (path + 6);
    }
  else if (g_str_has_prefix (path, "session/"))
    {
      bus->connection = dbus_bus_get_private (DBUS_BUS_SESSION, NULL);
      bus->name = g_strdup (path + 7);
    }
  else
    g_error ("fail.");

  _g_dbus_connection_integrate_with_main (bus->connection);

  bus->watches = NULL;

  dbus_connection_add_filter (bus->connection,
                              dconf_dbus_filter,
                              bus, NULL);

  return bus;
}

static gchar *
dconf_dbus_make_rule (DConfDBus   *bus,
                      const gchar *prefix)
{
  const gchar *relative;

  relative = dconf_dbus_find_relative (prefix);

  if (relative[0])
    return g_strdup_printf ("type='signal',"
                            "interface='ca.desrt.dconf',"
                            "member='Notify',"
                            "path='%s',"
                            "arg0path='%s'",
                            bus->name, relative);
  else
    return g_strdup_printf ("type='signal',"
                            "interface='ca.desrt.dconf',"
                            "member='Notify',"
                            "path='%s'", bus->name);
}

void
dconf_dbus_watch (DConfDBus       *bus,
                  const gchar     *prefix,
                  DConfDBusNotify  callback,
                  gpointer         user_data)
{
  DConfDBusWatch *watch;
  gchar *rule;

  watch = g_slice_new (DConfDBusWatch);
  watch->prefix = g_strdup (prefix);
  watch->callback = callback;
  watch->user_data = user_data;

  bus->watches = g_slist_prepend (bus->watches, watch);

  rule = dconf_dbus_make_rule (bus, prefix);
  dbus_bus_add_match (bus->connection, rule, NULL);
  g_free (rule);
}

void
dconf_dbus_unwatch (DConfDBus       *bus,
                    const gchar     *prefix,
                    DConfDBusNotify  callback,
                    gpointer         user_data)
{
  GSList **node;

  for (node = &bus->watches; *node; node = &(*node)->next)
    {
      DConfDBusWatch *watch = (*node)->data;

      if (watch->callback == callback && watch->user_data == user_data &&
          strcmp (watch->prefix, prefix) == 0)
        {
          gchar *rule;

          rule = dconf_dbus_make_rule (bus, watch->prefix);
          dbus_bus_remove_match (bus->connection, rule, NULL);
          g_free (rule);

          *node = g_slist_delete_link (*node, *node);
          g_free (watch->prefix);
          g_slice_free (DConfDBusWatch, watch);

          return;
        }
    }

  g_assert_not_reached ();
}

static void
dconf_dbus_from_gv (DBusMessageIter *iter,
                    GVariant        *value)
{
  switch (g_variant_get_type_class (value))
    {
     case G_VARIANT_TYPE_CLASS_BOOLEAN:
      {
        dbus_bool_t v = g_variant_get_boolean (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_BOOLEAN, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_BYTE:
      {
        guint8 v = g_variant_get_byte (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_BYTE, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_INT16:
      {
        gint16 v = g_variant_get_int16 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_INT16, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_UINT16:
      {
        guint16 v = g_variant_get_uint16 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_UINT16, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_INT32:
      {
        gint32 v = g_variant_get_int32 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_INT32, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_UINT32:
      {
        guint32 v = g_variant_get_uint32 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_UINT32, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_INT64:
      {
        gint64 v = g_variant_get_int64 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_INT64, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_UINT64:
      {
        guint64 v = g_variant_get_uint64 (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_UINT64, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_DOUBLE:
      {
        gdouble v = g_variant_get_double (value);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_DOUBLE, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_STRING:
      {
        const gchar *v = g_variant_get_string (value, NULL);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_STRING, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_OBJECT_PATH:
      {
        const gchar *v = g_variant_get_string (value, NULL);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_OBJECT_PATH, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_SIGNATURE:
      {
        const gchar *v = g_variant_get_string (value, NULL);
        dbus_message_iter_append_basic (iter, DBUS_TYPE_SIGNATURE, &v);
        break;
      }

     case G_VARIANT_TYPE_CLASS_VARIANT:
      {
        DBusMessageIter sub;
        GVariant *child;

        child = g_variant_get_child_value (value, 0);
        dbus_message_iter_open_container (iter, DBUS_TYPE_VARIANT,
                                          g_variant_get_type_string (child),
                                          &sub);
        dconf_dbus_from_gv (iter, child);
        dbus_message_iter_close_container (iter, &sub);
        g_variant_unref (child);
        break;
      }

     case G_VARIANT_TYPE_CLASS_MAYBE:
      g_error ("DBus does not (yet) support maybe types.");

     case G_VARIANT_TYPE_CLASS_ARRAY:
      {
        DBusMessageIter dbus_iter;
        const gchar *type_string;
        GVariantIter gv_iter;
        GVariant *item;

        type_string = g_variant_get_type_string (value);
        type_string++; /* skip the 'a' */

        dbus_message_iter_open_container (iter, DBUS_TYPE_ARRAY,
                                          type_string, &dbus_iter);
        g_variant_iter_init (&gv_iter, value);

        while ((item = g_variant_iter_next_value (&gv_iter)))
          dconf_dbus_from_gv (&dbus_iter, item);

        dbus_message_iter_close_container (iter, &dbus_iter);
        break;
      }

     case G_VARIANT_TYPE_CLASS_STRUCT:
      {
        DBusMessageIter dbus_iter;
        GVariantIter gv_iter;
        GVariant *item;

        dbus_message_iter_open_container (iter, DBUS_TYPE_STRUCT,
                                          NULL, &dbus_iter);
        g_variant_iter_init (&gv_iter, value);

        while ((item = g_variant_iter_next_value (&gv_iter)))
          dconf_dbus_from_gv (&dbus_iter, item);

        dbus_message_iter_close_container (iter, &dbus_iter);
        break;
      }

     case G_VARIANT_TYPE_CLASS_DICT_ENTRY:
      {
        DBusMessageIter dbus_iter;
        GVariant *key, *val;

        dbus_message_iter_open_container (iter, DBUS_TYPE_DICT_ENTRY,
                                          NULL, &dbus_iter);
        key = g_variant_get_child_value (value, 0);
        dconf_dbus_from_gv (&dbus_iter, key);
        g_variant_unref (key);

        val = g_variant_get_child_value (value, 1);
        dconf_dbus_from_gv (&dbus_iter, val);
        g_variant_unref (val);

        dbus_message_iter_close_container (iter, &dbus_iter);
        break;
      }

     default:
      g_assert_not_reached ();
    }
}

static gboolean
dconf_dbus_blocking_call (DConfDBus    *bus,
                          DBusMessage  *message,
                          const gchar  *reply_signature,
                          guint32      *sequence,
                          GError      **error)
{
  DBusError d_error = { 0, };
  DBusMessage *reply;

  reply = dbus_connection_send_with_reply_and_block (bus->connection,
                                                     message, -1, &d_error);
  dbus_message_unref (message);

  if (reply == NULL)
    {
      g_set_error (error, 0, 0, "%s: %s", d_error.name, d_error.message);
      return FALSE;
    }

  if (!dbus_message_has_signature (reply, reply_signature))
    {
      g_set_error (error, 0, 0, "DBus reply message has incorrect signature.");
      dbus_message_unref (reply);
      return FALSE;
    }

  if (sequence)
    dbus_message_get_args (reply, NULL,
                           DBUS_TYPE_UINT32, sequence,
                           DBUS_TYPE_INVALID);

  dbus_message_unref (reply);

  return TRUE;
}

gboolean
dconf_dbus_set (DConfDBus    *bus,
                const gchar  *key,
                GVariant     *value,
                guint32      *sequence,
                GError      **error)
{
  DBusMessageIter iter, variant;
  DBusMessage *message;

  {
    gchar *bus_name = g_strdup_printf ("ca.desrt.dconf.%s", bus->name + 1);
    message = dbus_message_new_method_call (bus_name, bus->name,
                                            "ca.desrt.dconf", "Set");
    g_free (bus_name);
  }

  dbus_message_iter_init_append (message, &iter);
  dbus_message_iter_append_basic (&iter, DBUS_TYPE_STRING, &key);
  dbus_message_iter_open_container (&iter, DBUS_TYPE_VARIANT,
                                    g_variant_get_type_string (value),
                                    &variant);
  dconf_dbus_from_gv (&variant, value);
  dbus_message_iter_close_container (&iter, &variant);

  return dconf_dbus_blocking_call (bus, message, "u", sequence, error);
}

gboolean
dconf_dbus_unset (DConfDBus    *bus,
                  const gchar  *key,
                  guint32      *sequence,
                  GError      **error)
{
  DBusMessageIter iter;
  DBusMessage *message;
  DBusMessage *reply;

  {
    gchar *bus_name = g_strdup_printf ("ca.desrt.dconf.%s", bus->name + 1);
    message = dbus_message_new_method_call (bus_name, bus->name,
                                            "ca.desrt.dconf", "Unset");
    g_free (bus_name);
  }

  dbus_message_iter_init_append (message, &iter);
  dbus_message_iter_append_basic (&iter, DBUS_TYPE_STRING, &key);

  reply = dbus_connection_send_with_reply_and_block (bus->connection,
                                                     message,
                                                     -1, NULL);

  return dconf_dbus_blocking_call (bus, message, "u", sequence, error);
}

gboolean
dconf_dbus_set_locked (DConfDBus    *bus,
                       const gchar  *key,
                       gboolean      locked,
                       GError      **error)
{
  DBusMessageIter iter;
  DBusMessage *message;
  dbus_bool_t val;

  {
    gchar *bus_name = g_strdup_printf ("ca.desrt.dconf.%s", bus->name + 1);
    message = dbus_message_new_method_call (bus_name, bus->name,
                                            "ca.desrt.dconf", "SetLocked");
    g_free (bus_name);
  }

  val = !!locked;

  dbus_message_iter_init_append (message, &iter);
  dbus_message_iter_append_basic (&iter, DBUS_TYPE_STRING, &key);
  dbus_message_iter_append_basic (&iter, DBUS_TYPE_BOOLEAN, &val);

  return dconf_dbus_blocking_call (bus, message, "", NULL, error);
}

typedef struct
{
  DConfDBusAsyncReadyCallback callback;
  gpointer user_data;
} DConfDBusClosure;

static DConfDBusClosure *
dconf_dbus_closure_new (DConfDBusAsyncReadyCallback callback,
                        gpointer                    user_data)
{
  DConfDBusClosure *closure;

  closure = g_slice_new (DConfDBusClosure);
  closure->callback = callback;
  closure->user_data = user_data;

  return closure;
}

static void
dconf_dbus_closure_fire (DConfDBusClosure *closure,
                         DBusPendingCall  *pending)
{
  closure->callback ((DConfDBusAsyncResult *) &pending, closure->user_data);
  g_slice_free (DConfDBusClosure, closure);
}

static void
dconf_dbus_merge_ready (DBusPendingCall *pending,
                        gpointer         user_data)
{
  DConfDBusClosure *closure = user_data;

  dconf_dbus_closure_fire (closure, pending);
}

static gboolean
dconf_dbus_append_to_iter (gpointer key,
                           gpointer value,
                           gpointer user_data)
{
  DBusMessageIter *iter = user_data;
  DBusMessageIter struc;
  DBusMessageIter var;

  dbus_message_iter_open_container (iter, DBUS_TYPE_STRUCT, NULL, &struc);
  dbus_message_iter_append_basic (&struc, DBUS_TYPE_STRING, &key);

  dbus_message_iter_open_container (&struc, DBUS_TYPE_VARIANT,
                                    g_variant_get_type_string (value),
                                    &var);
  dconf_dbus_from_gv (&var, value);
  dbus_message_iter_close_container (&struc, &var);

  dbus_message_iter_close_container (iter, &struc);

  return FALSE;
}

void
dconf_dbus_merge_tree_async (DConfDBus                   *bus,
                             const gchar                 *prefix,
                             GTree                       *values,
                             DConfDBusAsyncReadyCallback  callback,
                             gpointer                     user_data)
{
  DBusMessageIter iter, array;
  DBusPendingCall *pending;
  DBusMessage *message;

  {
    gchar *bus_name = g_strdup_printf ("ca.desrt.dconf.%s", bus->name + 1);
    message = dbus_message_new_method_call (bus_name, bus->name,
                                            "ca.desrt.dconf", "Merge");
    g_free (bus_name);
  }

  dbus_message_iter_init_append (message, &iter);
  dbus_message_iter_append_basic (&iter, DBUS_TYPE_STRING, &prefix);
  dbus_message_iter_open_container (&iter, DBUS_TYPE_ARRAY, "(sv)", &array);
  g_tree_foreach (values, dconf_dbus_append_to_iter, &array);
  dbus_message_iter_close_container (&iter, &array);

  dbus_connection_send_with_reply (bus->connection, message, &pending, -1);
  dbus_pending_call_set_notify (pending, dconf_dbus_merge_ready,
                                dconf_dbus_closure_new (callback, user_data),
                                NULL);
}

struct OPAQUE_TYPE__DConfDBusAsyncResult
{
  DBusPendingCall *pending;
};

gboolean
dconf_dbus_merge_finish (DConfDBusAsyncResult  *result,
                         guint32               *sequence,
                         GError               **error)
{
  DBusMessage *reply;
  gboolean success;

  reply = dbus_pending_call_steal_reply (result->pending);
  if (dbus_message_get_type (reply) == DBUS_MESSAGE_TYPE_ERROR)
    {
      g_set_error (error, 0, 0, "broken.");
      success = FALSE;
    }
  else if (!dbus_message_has_signature (reply, "u"))
    {
      g_set_error (error, 0, 0, "bad sig");
      success = FALSE;
    }
  else
    {
      dbus_message_get_args (reply, NULL,
                             DBUS_TYPE_UINT32, sequence,
                             DBUS_TYPE_INVALID);
      success = TRUE;
    }


  dbus_message_unref (reply);

  return success;
}

/* ------------------------------------------------------------------------ */
/* all code past this point is for mainloop integration.
 *
 * this code was lifted from common/gdbusutils.c in gvfs.
 * it has been slightly modified to remove its dependence on libgio.
 *
 * Copyright (C) 2006-2007 Red Hat, Inc.
 * Author: Alexander Larsson <alexl@redhat.com>
 * Modified: Ryan Lortie <desrt@desrt.ca>
 */

typedef gboolean (*GFDSourceFunc) (gpointer data,
                                   GIOCondition condition,
                                   int fd);

static void
_g_dbus_oom (void)
{
  g_error ("DBus failed with out of memory error");
}

/*************************************************************************
 *             Helper fd source                                          *
 ************************************************************************/

typedef struct 
{
  GSource source;
  GPollFD pollfd;
} FDSource;

static gboolean 
fd_source_prepare (GSource  *source,
		   gint     *timeout)
{
  *timeout = -1;
  
  return FALSE;
}

static gboolean 
fd_source_check (GSource  *source)
{
  FDSource *fd_source = (FDSource *)source;

  return fd_source->pollfd.revents != 0;
}

static gboolean
fd_source_dispatch (GSource     *source,
		    GSourceFunc  callback,
		    gpointer     user_data)

{
  GFDSourceFunc func = (GFDSourceFunc)callback;
  FDSource *fd_source = (FDSource *)source;

  g_assert (func != NULL);

  return (*func) (user_data, fd_source->pollfd.revents, fd_source->pollfd.fd);
}

static GSourceFuncs fd_source_funcs = {
  fd_source_prepare,
  fd_source_check,
  fd_source_dispatch,
  NULL
};

/* Two __ to avoid conflict with gio version */
static GSource *
__g_fd_source_new (int fd,
		   gushort events)
{
  GSource *source;
  FDSource *fd_source;

  source = g_source_new (&fd_source_funcs, sizeof (FDSource));
  fd_source = (FDSource *)source;

  fd_source->pollfd.fd = fd;
  fd_source->pollfd.events = events;
  g_source_add_poll (source, &fd_source->pollfd);

  return source;
}

/*************************************************************************
 *                                                                       *
 *      dbus mainloop integration for async ops                          *
 *                                                                       *
 *************************************************************************/

static gint32 main_integration_data_slot = -1;
static GOnce once_init_main_integration = G_ONCE_INIT;

/**
 * A GSource subclass for dispatching DBusConnection messages.
 * We need this on top of the IO handlers, because sometimes
 * there are messages to dispatch queued up but no IO pending.
 * 
 * The source is owned by the connection (and the main context
 * while that is alive)
 */
typedef struct 
{
  GSource source;
  
  DBusConnection *connection;
  GSList *ios;
  GSList *timeouts;
} DBusSource;

typedef struct
{
  DBusSource *dbus_source;
  GSource *source;
  DBusWatch *watch;
} IOHandler;

typedef struct
{
  DBusSource *dbus_source;
  GSource *source;
  DBusTimeout *timeout;
} TimeoutHandler;

static gpointer
main_integration_init (gpointer arg)
{
  if (!dbus_connection_allocate_data_slot (&main_integration_data_slot))
    g_error ("Unable to allocate data slot");

  return NULL;
}

static gboolean
dbus_source_prepare (GSource *source,
		     gint    *timeout)
{
  DBusConnection *connection = ((DBusSource *)source)->connection;
  
  *timeout = -1;

  return (dbus_connection_get_dispatch_status (connection) == DBUS_DISPATCH_DATA_REMAINS);  
}

static gboolean
dbus_source_check (GSource *source)
{
  return FALSE;
}

static gboolean
dbus_source_dispatch (GSource     *source,
		      GSourceFunc  callback,
		      gpointer     user_data)
{
  DBusConnection *connection = ((DBusSource *)source)->connection;

  dbus_connection_ref (connection);

  /* Only dispatch once - we don't want to starve other GSource */
  dbus_connection_dispatch (connection);
  
  dbus_connection_unref (connection);

  return TRUE;
}

static gboolean
io_handler_dispatch (gpointer data,
                     GIOCondition condition,
                     int fd)
{
  IOHandler *handler = data;
  guint dbus_condition = 0;
  DBusConnection *connection;

  connection = handler->dbus_source->connection;
  
  if (connection)
    dbus_connection_ref (connection);
  
  if (condition & G_IO_IN)
    dbus_condition |= DBUS_WATCH_READABLE;
  if (condition & G_IO_OUT)
    dbus_condition |= DBUS_WATCH_WRITABLE;
  if (condition & G_IO_ERR)
    dbus_condition |= DBUS_WATCH_ERROR;
  if (condition & G_IO_HUP)
    dbus_condition |= DBUS_WATCH_HANGUP;

  /* Note that we don't touch the handler after this, because
   * dbus may have disabled the watch and thus killed the
   * handler.
   */
  dbus_watch_handle (handler->watch, dbus_condition);
  handler = NULL;

  if (connection)
    dbus_connection_unref (connection);
  
  return TRUE;
}

static void
io_handler_free (IOHandler *handler)
{
  DBusSource *dbus_source;
  
  dbus_source = handler->dbus_source;
  dbus_source->ios = g_slist_remove (dbus_source->ios, handler);
  
  g_source_destroy (handler->source);
  g_source_unref (handler->source);
  g_free (handler);
}

static void
dbus_source_add_watch (DBusSource *dbus_source,
		       DBusWatch *watch)
{
  guint flags;
  GIOCondition condition;
  IOHandler *handler;
  int fd;

  if (!dbus_watch_get_enabled (watch))
    return;
  
  g_assert (dbus_watch_get_data (watch) == NULL);
  
  flags = dbus_watch_get_flags (watch);

  condition = G_IO_ERR | G_IO_HUP;
  if (flags & DBUS_WATCH_READABLE)
    condition |= G_IO_IN;
  if (flags & DBUS_WATCH_WRITABLE)
    condition |= G_IO_OUT;

  handler = g_new0 (IOHandler, 1);
  handler->dbus_source = dbus_source;
  handler->watch = watch;

#if (DBUS_MAJOR_VERSION == 1 && DBUS_MINOR_VERSION == 1 && DBUS_MICRO_VERSION >= 1) || (DBUS_MAJOR_VERSION == 1 && DBUS_MINOR_VERSION > 1) || (DBUS_MAJOR_VERSION > 1)
  fd = dbus_watch_get_unix_fd (watch);
#else
  fd = dbus_watch_get_fd (watch);
#endif
    
  handler->source = __g_fd_source_new (fd, condition);
  g_source_set_callback (handler->source,
			 (GSourceFunc) io_handler_dispatch, handler,
                         NULL);
  g_source_attach (handler->source, NULL);
 
  dbus_source->ios = g_slist_prepend (dbus_source->ios, handler);
  dbus_watch_set_data (watch, handler,
		       (DBusFreeFunction)io_handler_free);
}

static void
dbus_source_remove_watch (DBusSource *dbus_source,
			  DBusWatch *watch)
{
  dbus_watch_set_data (watch, NULL, NULL);
}

static void
timeout_handler_free (TimeoutHandler *handler)
{
  DBusSource *dbus_source;

  dbus_source = handler->dbus_source;
  dbus_source->timeouts = g_slist_remove (dbus_source->timeouts, handler);

  g_source_destroy (handler->source);
  g_source_unref (handler->source);
  g_free (handler);
}

static gboolean
timeout_handler_dispatch (gpointer      data)
{
  TimeoutHandler *handler = data;

  dbus_timeout_handle (handler->timeout);
  
  return TRUE;
}

static void
dbus_source_add_timeout (DBusSource *dbus_source,
			 DBusTimeout *timeout)
{
  TimeoutHandler *handler;
  
  if (!dbus_timeout_get_enabled (timeout))
    return;
  
  g_assert (dbus_timeout_get_data (timeout) == NULL);

  handler = g_new0 (TimeoutHandler, 1);
  handler->dbus_source = dbus_source;
  handler->timeout = timeout;

  handler->source = g_timeout_source_new (dbus_timeout_get_interval (timeout));
  g_source_set_callback (handler->source,
			 timeout_handler_dispatch, handler,
                         NULL);
  g_source_attach (handler->source, NULL);

  /* handler->source is owned by the context here */
  dbus_source->timeouts = g_slist_prepend (dbus_source->timeouts, handler);

  dbus_timeout_set_data (timeout, handler,
			 (DBusFreeFunction)timeout_handler_free);
}

static void
dbus_source_remove_timeout (DBusSource *source,
			    DBusTimeout *timeout)
{
  dbus_timeout_set_data (timeout, NULL, NULL);
}

static dbus_bool_t
add_watch (DBusWatch *watch,
	   gpointer   data)
{
  DBusSource *dbus_source = data;

  dbus_source_add_watch (dbus_source, watch);
  
  return TRUE;
}

static void
remove_watch (DBusWatch *watch,
	      gpointer   data)
{
  DBusSource *dbus_source = data;

  dbus_source_remove_watch (dbus_source, watch);
}

static void
watch_toggled (DBusWatch *watch,
               void      *data)
{
  /* Because we just exit on OOM, enable/disable is
   * no different from add/remove */
  if (dbus_watch_get_enabled (watch))
    add_watch (watch, data);
  else
    remove_watch (watch, data);
}

static dbus_bool_t
add_timeout (DBusTimeout *timeout,
	     void        *data)
{
  DBusSource *source = data;
  
  if (!dbus_timeout_get_enabled (timeout))
    return TRUE;

  dbus_source_add_timeout (source, timeout);

  return TRUE;
}

static void
remove_timeout (DBusTimeout *timeout,
		void        *data)
{
  DBusSource *source = data;

  dbus_source_remove_timeout (source, timeout);
}

static void
timeout_toggled (DBusTimeout *timeout,
                 void        *data)
{
  /* Because we just exit on OOM, enable/disable is
   * no different from add/remove
   */
  if (dbus_timeout_get_enabled (timeout))
    add_timeout (timeout, data);
  else
    remove_timeout (timeout, data);
}

static void
wakeup_main (void *data)
{
  g_main_context_wakeup (NULL);
}

static const GSourceFuncs dbus_source_funcs = {
  dbus_source_prepare,
  dbus_source_check,
  dbus_source_dispatch
};

/* Called when the connection dies or when we're unintegrating from mainloop */
static void
dbus_source_free (DBusSource *dbus_source)
{
  while (dbus_source->ios)
    {
      IOHandler *handler = dbus_source->ios->data;
      
      dbus_watch_set_data (handler->watch, NULL, NULL);
    }

  while (dbus_source->timeouts)
    {
      TimeoutHandler *handler = dbus_source->timeouts->data;
      
      dbus_timeout_set_data (handler->timeout, NULL, NULL);
    }

  /* Remove from mainloop */
  g_source_destroy ((GSource *)dbus_source);

  g_source_unref ((GSource *)dbus_source);
}

static void
_g_dbus_connection_remove_from_main (DBusConnection *connection)
{
  g_once (&once_init_main_integration, main_integration_init, NULL);

  if (!dbus_connection_set_data (connection,
				 main_integration_data_slot,
				 NULL, NULL))
    _g_dbus_oom ();
}

static void
_g_dbus_connection_integrate_with_main (DBusConnection *connection)
{
  DBusSource *dbus_source;

  g_once (&once_init_main_integration, main_integration_init, NULL);
  
  g_assert (connection != NULL);

  _g_dbus_connection_remove_from_main (connection);

  dbus_source = (DBusSource *)
    g_source_new ((GSourceFuncs*)&dbus_source_funcs,
		  sizeof (DBusSource));
  
  dbus_source->connection = connection;
  
  if (!dbus_connection_set_watch_functions (connection,
                                            add_watch,
                                            remove_watch,
                                            watch_toggled,
                                            dbus_source, NULL))
    _g_dbus_oom ();

  if (!dbus_connection_set_timeout_functions (connection,
                                              add_timeout,
                                              remove_timeout,
                                              timeout_toggled,
                                              dbus_source, NULL))
    _g_dbus_oom ();
    
  dbus_connection_set_wakeup_main_function (connection,
					    wakeup_main,
					    dbus_source, NULL);

  /* Owned by both connection and mainloop (until destroy) */
  g_source_attach ((GSource *)dbus_source, NULL);

  if (!dbus_connection_set_data (connection,
				 main_integration_data_slot,
				 dbus_source, (DBusFreeFunction)dbus_source_free))
    _g_dbus_oom ();
}
