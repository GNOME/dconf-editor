lib_LTLIBRARIES = libdconf.la

AM_CFLAGS = -I$(top_srcdir)/common -I$(top_srcdir)/engine $(gio_CFLAGS) -I$(top_srcdir)/gvdb
libdconf_la_SOURCES = dconf-client.c ../common/dconf-paths.c ../engine/dconf-engine.c ../gvdb/gvdb-reader.c
libdconf_la_LIBADD = $(gio_LIBS)
