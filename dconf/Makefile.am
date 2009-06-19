lib_LTLIBRARIES = libdconf.la

AM_CFLAGS = $(glib_CFLAGS) $(dbus_CFLAGS) -Wall -g -I../common

libdconf_la_LIBADD = $(glib_LIBS) $(dbus_LIBS)
libdconf_la_SOURCES = dconf-reader.c dconf-core.c dconf-base.c dconf-config.c dconf-dbus.c

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf.pc

dconfincludedir = $(includedir)/dconf
dconfinclude_HEADERS = dconf.h

noinst_HEADERS = dconf-private-types.h dconf-reader.h dconf-dbus.h
