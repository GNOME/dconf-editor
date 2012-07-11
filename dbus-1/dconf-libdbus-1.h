#ifndef __dconf_libdbus_1_h__
#define __dconf_libdbus_1_h__

#include <dbus/dbus.h>
#include <gio/gio.h>

G_GNUC_INTERNAL
void                    dconf_libdbus_1_provide_bus                     (GBusType        bus_type,
                                                                         DBusConnection *connection);

#endif /* __dconf_libdbus_1_h__ */
