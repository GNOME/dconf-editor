AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings -D__dconf_h__ -fPIC -DPIC
CFLAGS += -Wno-error
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/gvdb -I$(top_srcdir)/engine $(gio_CFLAGS)

shlibdir=$(libdir)
shlib_PROGRAMS = libdconf.so.0.0.0
nodist_noinst_DATA = libdconf.so.0 libdconf.so

libdconf.so.0 libdconf.so: libdconf.so.0.0.0
	$(AM_V_GEN) ln -fs libdconf.so.0.0.0 $@

install-data-hook:
	ln -fs libdconf.so.0.0.0 $(DESTDIR)$(shlibdir)/libdconf.so.0
	ln -fs libdconf.so.0.0.0 $(DESTDIR)$(shlibdir)/libdconf.so

uninstall-hook:
	rm -f $(DESTDIR)$(shlibdir)/libdconf.so.0
	rm -f $(DESTDIR)$(shlibdir)/libdconf.so

dconfinclude_HEADERS = \
	dconf-client.h	\
	dconf.h

libdconf_so_0_0_0_LDADD = $(gio_LIBS)
libdconf_so_0_0_0_LDFLAGS = -shared -Wl,-soname=libdconf.so.0
libdconf_so_0_0_0_SOURCES = \
	../common/dconf-shmdir.c	\
	../common/dconf-paths.c		\
	../engine/dconf-engine.c	\
	../gvdb/gvdb-reader.c		\
	dconf-client.vala engine.vapi
libdconf_so_0_0_0_VALAFLAGS = --library dconf --pkg=gio-2.0

EXTRA_DIST = dconf.vapi extra-docs.c
dconf.vapi: libdconf.so.0

dconf.deps:
	$(AM_V_GEN) echo gio-2.0 > dconf.deps

vapi_DATA = dconf.vapi dconf.deps
vapidir = $(datadir)/vala/vapi

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf.pc

CLEANFILES = dconf.deps libdconf.so.0 libdconf.so
