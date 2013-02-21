include $(top_srcdir)/Makefile.gtester

shlibdir=$(libdir)
shlib_PROGRAMS = libdconf.so.1.0.0
nodist_noinst_DATA = libdconf.so.1 libdconf.so
noinst_LIBRARIES = libdconf-client.a

libdconf.so.1 libdconf.so: libdconf.so.1.0.0
	$(AM_V_GEN) ln -fs libdconf.so.1.0.0 $@

install-data-hook:
	ln -fs libdconf.so.1.0.0 $(DESTDIR)$(shlibdir)/libdconf.so.1
	ln -fs libdconf.so.1.0.0 $(DESTDIR)$(shlibdir)/libdconf.so

uninstall-hook:
	rm -f $(DESTDIR)$(shlibdir)/libdconf.so.1
	rm -f $(DESTDIR)$(shlibdir)/libdconf.so

dconfinclude_HEADERS = dconf.h
dconfclientinclude_HEADERS = dconf-client.h
dconfclientincludedir = $(dconfincludedir)/client

libdconf_client_a_CFLAGS = $(gio_CFLAGS) -DG_LOG_DOMAIN=\"dconf\"
libdconf_client_a_SOURCES = \
	dconf-client.c

libdconf_so_1_0_0_CFLAGS = $(libdconf_client_a_CFLAGS) -fPIC -DPIC
libdconf_so_1_0_0_LDADD = \
	../engine/libdconf-engine-shared.a		\
	../common/libdconf-common-shared.a		\
	../gdbus/libdconf-gdbus-thread-shared.a		\
	../gvdb/libgvdb-shared.a			\
	../shm/libdconf-shm-shared.a			\
	$(gio_LIBS)
libdconf_so_1_0_0_LDFLAGS = -shared -Wl,-soname=libdconf.so.1
libdconf_so_1_0_0_SOURCES = $(libdconf_client_a_SOURCES)

EXTRA_DIST = dconf.vapi dconf.deps

vapi_DATA = dconf.vapi dconf.deps
vapidir = $(datadir)/vala/vapi

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf.pc

CLEANFILES = libdconf.so.1 libdconf.so
