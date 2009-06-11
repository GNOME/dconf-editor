lib_LTLIBRARIES = libdconf.la
noinst_PROGRAMS = test

AM_CFLAGS = $(glib_CFLAGS) $(dbus_CFLAGS) -Wall -g

test_LDADD = libdconf.la $(glib_LIBS) $(dbus_LIBS)
test_SOURCES = test.c

libdconf_la_LIBADD = $(glib_LIBS) $(dbus_LIBS) $(gio_LIBS)
libdconf_la_SOURCES = dconf-reader.c dconf-core.c dconf-base.c dconf-config.c dconf-dbus.c

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf.pc

dconfincludedir = $(includedir)/dconf
dconfinclude_HEADERS = dconf-core.h dconf.h dconf-base.h
