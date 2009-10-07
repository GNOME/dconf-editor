AM_CFLAGS = -I$(top_srcdir)/common $(glib_CFLAGS) $(dbus_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g

DEFS = -DDCONF_CONF=\"$(sysconfdir)/dconf/dconf.conf\"

lib_LTLIBRARIES = libdconf.la

libdconf_la_LIBADD = $(glib_LIBS) $(dbus_LIBS)
libdconf_la_SOURCES = \
	dconf-reader.c		\
	dconf-config.c		\
	dconf-dbus.c		\
	dconf.c	

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf.pc

dconfincludedir = $(includedir)/dconf
dconfinclude_HEADERS = dconf.h

noinst_HEADERS = \
	dconf-private-types.h	\
	dconf-reader.h		\
	dconf-dbus.h		\
	dconf-config.h
