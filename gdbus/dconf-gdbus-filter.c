#include "../engine/dconf-engine.h"




typedef struct
{
  gpointer data; /* either GDBusConnection or GError */
  guint    is_error;
  guint    waiting_for_serial;
  GQueue   queue;
} ConnectionState;

typedef struct
{
  guint32                serial;
  DConfEngineCallHandle *handle;
} DConfGDBusCall;

static ConnectionState connections[3];
static GMutex dconf_gdbus_lock;

static GBusType
connection_state_get_bus_type (ConnectionState *state)
{
  return state - connections;
}

static gboolean
connection_state_ensure_success (ConnectionState  *state,
                                 GError          **error)
{
  if (state->is_error)
    {
      if (error)
        *error = g_error_copy (state->data);

      return FALSE;
    }

  return TRUE;
}

static GDBusConnection *
connection_state_get_connection (ConnectionState *state)
{
  g_assert (!state->is_error);

  return state->data;
}

/* This function can be slow (as compared to the one below). */
static void
dconf_gdbus_handle_reply (ConnectionState *state,
                          GDBusMessage    *message)
{
  DConfEngineCallHandle *handle;
  GError *error = NULL;
  GVariant *body;

  g_mutex_lock (&dconf_gdbus_lock);
  {
    DConfGDBusCall *call;

    call = g_queue_pop_head (&state->queue);
    g_assert_cmpuint (g_dbus_message_get_reply_serial (message), ==, call->serial);
    handle = call->handle;

    g_slice_free (DConfGDBusCall, call);

    call = g_queue_peek_head (&state->queue);
    if (call)
      g_atomic_int_set (&state->waiting_for_serial, call->serial);
    else
      g_atomic_int_set (&state->waiting_for_serial, -1);
  }
  g_mutex_unlock (&dconf_gdbus_lock);

  body = g_dbus_message_get_body (message);

  if (g_dbus_message_get_message_type (message) == G_DBUS_MESSAGE_TYPE_ERROR)
    {
      const GVariantType *first_child_type;
      const gchar *error_message = NULL;

      first_child_type = g_variant_type_first (g_variant_get_type (body));

      if (g_variant_type_equal (first_child_type, G_VARIANT_TYPE_STRING))
        g_variant_get_child (body, 0, "&s", &error_message);

      error = g_dbus_error_new_for_dbus_error (g_dbus_message_get_error_name (message), error_message);
      body = NULL;
    }

  dconf_engine_call_handle_reply (handle, body, error);

  if (error)
    g_error_free (error);
}

/* We optimise for this function being super-efficient since it gets run
 * on every single D-Bus message in or out.
 *
 * We want to bail out as quickly as possible in the case that this
 * message does not interest us.  That means we should not hold locks or
 * anything like that.
 *
 * In the case that this message _does_ interest us (which should be
 * rare) we can take a lot more time.
 */
static GDBusMessage *
dconf_gdbus_filter_function (GDBusConnection *connection,
                             GDBusMessage    *message,
                             gboolean         incoming,
                             gpointer         user_data)
{
  ConnectionState *state = user_data;

  if (incoming)
    {
      switch (g_dbus_message_get_message_type (message))
        {
        case G_DBUS_MESSAGE_TYPE_SIGNAL:
          {
            const gchar *interface;

            interface = g_dbus_message_get_interface (message);
            if (interface && g_str_equal (interface, "ca.desrt.dconf.Writer"))
              dconf_engine_handle_dbus_signal (connection_state_get_bus_type (state),
                                               g_dbus_message_get_sender (message),
                                               g_dbus_message_get_path (message),
                                               g_dbus_message_get_member (message),
                                               g_dbus_message_get_body (message));

            /* Others could theoretically be interested in this... */
          }
          break;

        case G_DBUS_MESSAGE_TYPE_METHOD_RETURN:
        case G_DBUS_MESSAGE_TYPE_ERROR:
          if G_UNLIKELY (g_dbus_message_get_reply_serial (message) == g_atomic_int_get (&state->waiting_for_serial))
            {
              /* This is definitely for us. */
              dconf_gdbus_handle_reply (state, message);

              /* Nobody else should be interested in it. */
              g_clear_object (&message);
            }
          break;

        default:
          break;
        }
    }

  return message;
}

static ConnectionState *
dconf_gdbus_get_connection_state (GBusType   bus_type,
                                  GError   **error)
{
  ConnectionState *state;

  g_assert (bus_type < G_N_ELEMENTS (connections));

  state = &connections[bus_type];

  if (g_once_init_enter (&state->data))
    {
      GDBusConnection *connection;
      GError *error = NULL;
      gpointer result;

      /* This will only block the first time...
       *
       * Optimising this away is probably not worth the effort.
       */
      connection = g_bus_get_sync (bus_type, NULL, &error);

      if (connection)
        {
          g_dbus_connection_add_filter (connection, dconf_gdbus_filter_function, state, NULL);
          result = connection;
          state->is_error = FALSE;
        }
      else
        {
          result = error;
          state->is_error = TRUE;
        }

      g_once_init_leave (&state->data, result);
    }

  if (!connection_state_ensure_success (state, error))
    return FALSE;

  return state;
}

gboolean
dconf_engine_dbus_call_async_func (GBusType                bus_type,
                                   const gchar            *bus_name,
                                   const gchar            *object_path,
                                   const gchar            *interface_name,
                                   const gchar            *method_name,
                                   GVariant               *parameters,
                                   DConfEngineCallHandle  *handle,
                                   GError                **error)
{
  ConnectionState *state;
  GDBusMessage *message;
  DConfGDBusCall *call;
  gboolean success;

  state = dconf_gdbus_get_connection_state (bus_type, error);

  if (state == NULL)
    {
      g_variant_unref (g_variant_ref_sink (parameters));
      return FALSE;
    }

  message = g_dbus_message_new_method_call (bus_name, object_path, interface_name, method_name);
  g_dbus_message_set_body (message, parameters);

  g_mutex_lock (&dconf_gdbus_lock);
  {
    volatile guint *serial_ptr;
    guint my_serial;

    /* We need to set the serial in call->serial.  Sometimes we also
     * need to set it in state->waiting_for_serial (in the case that no
     * other items are queued yet).
     *
     * g_dbus_connection_send_message() only has one out_serial parameter
     * so we can only set one of them atomically.  If needed, we elect
     * to set the waiting_for_serial because that is the one that is
     * accessed from the filter function without holding the lock.
     *
     * The serial number in the call structure is only accessed after the
     * lock is acquired which allows us to take our time setting it (for
     * as long as we're still holding the lock).
     *
     * In the case that waiting_for_serial should not be set we just use
     * a local variable and use that to fill call->serial.
     *
     * Also: the queue itself isn't accessed until after the lock is
     * taken, so we can delay adding the call to the queue until we know
     * that the sending of the message was successful.
     */

    if (g_queue_is_empty (&state->queue))
      serial_ptr = &state->waiting_for_serial;
    else
      serial_ptr = &my_serial;

    success = g_dbus_connection_send_message (connection_state_get_connection (state), message,
                                              G_DBUS_SEND_MESSAGE_FLAGS_NONE, serial_ptr, error);

    if (success)
      {
        call = g_slice_new (DConfGDBusCall);

        call->handle = handle;
        call->serial = *serial_ptr;

        g_queue_push_tail (&state->queue, call);
      }
  }
  g_mutex_unlock (&dconf_gdbus_lock);

  g_object_unref (message);

  return success;
}

GVariant *
dconf_engine_dbus_call_sync_func (GBusType             bus_type,
                                  const gchar         *bus_name,
                                  const gchar         *object_path,
                                  const gchar         *interface_name,
                                  const gchar         *method_name,
                                  GVariant            *parameters,
                                  const GVariantType  *reply_type,
                                  GError             **error)
{
  ConnectionState *state;

  state = dconf_gdbus_get_connection_state (bus_type, error);

  if (state == NULL)
    {
      g_variant_unref (g_variant_ref_sink (parameters));

      return NULL;
    }

  return g_dbus_connection_call_sync (connection_state_get_connection (state),
                                      bus_name, object_path, interface_name, method_name, parameters, reply_type,
                                      G_DBUS_CALL_FLAGS_NONE, -1, NULL, error);
}

#ifndef PIC
void
dconf_engine_dbus_init_for_testing (void)
{
}
#endif
