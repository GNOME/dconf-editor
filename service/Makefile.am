AM_CFLAGS = -I$(top_srcdir)/dconf $(glib_CFLAGS) $(dbus_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g

libexec_PROGRAMS = dconf-service

dconf_service_LDADD = $(glib_LIBS) $(dbus_LIBS) ../dconf/libdconf.la
dconf_service_SOURCES = dconf-dbus-service.c
