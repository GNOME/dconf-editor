AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings
INCLUDES = -I$(top_srcdir)/{common,gvdb,engine} $(gio_CFLAGS)

lib_LTLIBRARIES = libdconf.la

dconfinclude_HEADERS = \
	dconf-client.h	\
	dconf.h

libdconf_la_LIBADD = $(gio_LIBS)
libdconf_la_SOURCES = \
	../common/dconf-paths.c		\
	../engine/dconf-engine.c	\
	../gvdb/gvdb-reader.c		\
	dconf-client.c

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf.pc
