lib_LTLIBRARIES = libdconf.la

AM_CFLAGS = $(glib_CFLAGS) $(dbus_CFLAGS) $(gbus_CFLAGS) -Wall

libdconf_la_LIBADD = $(glib_LIBS) $(dbus_LIBS) $(gbus_LIBS)
libdconf_la_SOURCES = dconf-reader.c dconf-core.c dconf-base.c
