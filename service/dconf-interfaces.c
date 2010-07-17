#include "dconf-interfaces.h"

static const GDBusArgInfo name_arg = { -1, (gchar *) "name", (gchar *) "s" };
static const GDBusArgInfo path_arg = { -1, (gchar *) "path", (gchar *) "s" };
static const GDBusArgInfo names_arg = { -1, (gchar *) "names", (gchar *) "as" };
static const GDBusArgInfo serial_arg = { -1, (gchar *) "serial", (gchar *) "t" };
static const GDBusArgInfo value_arg = { -1, (gchar *) "value", (gchar *) "av" };
static const GDBusArgInfo values_arg = { -1, (gchar *) "values", (gchar *) "a(sav)" };
static const GDBusArgInfo locked_arg = { -1, (gchar *) "locked", (gchar *) "b" };

static const GDBusArgInfo *write_in[] = { &name_arg, &value_arg, NULL };
static const GDBusArgInfo *write_out[] = { &serial_arg, NULL };
static const GDBusArgInfo *many_in[] = { &path_arg, &values_arg, NULL };
static const GDBusArgInfo *many_out[] = { &serial_arg, NULL };
static const GDBusArgInfo *notify_args[] = { &path_arg, &names_arg, NULL };
static const GDBusArgInfo *setlock_in[] = { &name_arg, &locked_arg, NULL };
static const GDBusArgInfo *setlock_out[] = { NULL };

static const GDBusMethodInfo write_method = {
  -1, (gchar *) "Write",
  (GDBusArgInfo **) write_in,
  (GDBusArgInfo **) write_out
};

static const GDBusMethodInfo writemany_method = {
  -1, (gchar *) "WriteMany",
  (GDBusArgInfo **) many_in,
  (GDBusArgInfo **) many_out
};

static const GDBusMethodInfo setlock_method = {
  -1, (gchar *) "SetLock",
  (GDBusArgInfo **) setlock_in,
  (GDBusArgInfo **) setlock_out
};

static const GDBusSignalInfo notify_signal = {
  -1, (gchar *) "Notify",
  (GDBusArgInfo **) notify_args
};

static const GDBusPropertyInfo shmdir_property = {
  -1, (gchar *) "ShmDirectory", (gchar *) "s", G_DBUS_PROPERTY_INFO_FLAGS_READABLE
};

static const GDBusMethodInfo *writer_methods[] = {
  &write_method, &writemany_method, &setlock_method, NULL
};

static const GDBusSignalInfo *writer_signals[] = {
  &notify_signal, NULL
};

static const GDBusPropertyInfo *writer_info_properties[] = {
  &shmdir_property, NULL
};

const GDBusInterfaceInfo ca_desrt_dconf_Writer = {
  -1, (gchar *) "ca.desrt.dconf.Writer",
  (GDBusMethodInfo **) writer_methods,
  (GDBusSignalInfo **) writer_signals,
  (GDBusPropertyInfo **) NULL
};

const GDBusInterfaceInfo ca_desrt_dconf_WriterInfo = {
  -1, (gchar *) "ca.desrt.dconf.WriterInfo",
  (GDBusMethodInfo **) NULL,
  (GDBusSignalInfo **) NULL,
  (GDBusPropertyInfo **) writer_info_properties
};
