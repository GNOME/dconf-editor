if HAVE_INTROSPECTION
include $(INTROSPECTION_MAKEFILE)

dconf-0.3.gir: libdconf.la
dconf_0_3_gir_INCLUDES = Gio-2.0
dconf_0_3_gir_CFLAGS = $(INCLUDES)
dconf_0_3_gir_LIBS = libdconf.la
dconf_0_3_gir_FILES = dconf-client.c dconf-client.h
INTROSPECTION_GIRS = dconf-0.3.gir

girdir = $(datadir)/gir-1.0
dist_gir_DATA = $(INTROSPECTION_GIRS)

typelibdir = $(libdir)/girepository-1.0
typelib_DATA = $(INTROSPECTION_GIRS:.gir=.typelib)
endif

AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings -D__dconf_h__
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/gvdb -I$(top_srcdir)/engine $(gio_CFLAGS)

lib_LTLIBRARIES = libdconf.la

dconfinclude_HEADERS = \
	dconf-client.h	\
	dconf.h

libdconf_la_LIBADD = $(gio_LIBS)
libdconf_la_SOURCES = \
	../common/dconf-shmdir.c	\
	../common/dconf-paths.c		\
	../engine/dconf-engine.c	\
	../gvdb/gvdb-reader.c		\
	dconf-client.vala engine.vapi
libdconf_la_VALAFLAGS = --library dconf --pkg=gio-2.0

dconf.vapi: libdconf.la

dconf.deps:
	echo gio-2.0 > dconf.deps

vapi_DATA = dconf.vapi dconf.deps
vapidir = $(datadir)/vala/vapi

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf.pc

CLEANFILES = $(dist_gir_DATA) $(typelib_DATA)
