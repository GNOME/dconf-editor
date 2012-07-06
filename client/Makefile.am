include $(top_srcdir)/Makefile.gtester

AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings -fPIC -DPIC
CFLAGS += -Wno-error -Wno-unused-but-set-variable -Wno-unused-variable
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

libdconf_so_0_0_0_LDADD = $(gio_LIBS) ../common/libdconf-common-shared.a ../engine/libdconf-engine.a ../gdbus/libdconf-gdbus.a
libdconf_so_0_0_0_LDFLAGS = -shared -Wl,-soname=libdconf.so.0
libdconf_so_0_0_0_SOURCES = \
	dconf-client.c

EXTRA_DIST = dconf.vapi

vapi_DATA = dconf.vapi dconf.deps
vapidir = $(datadir)/vala/vapi

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf.pc

CLEANFILES = libdconf.so.0 libdconf.so
