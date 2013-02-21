include $(top_srcdir)/Makefile.gtester

noinst_LIBRARIES = libdconf-libdbus-1.a libdconf-libdbus-1-shared.a

libdconf_libdbus_1_a_CFLAGS = $(dbus_CFLAGS) $(glib_CFLAGS) -DG_LOG_DOMAIN=\"dconf\"
libdconf_libdbus_1_a_SOURCES = \
	dconf-libdbus-1.h		\
	dconf-libdbus-1.c

libdconf_libdbus_1_shared_a_CFLAGS = $(libdconf_libdbus_1_a_CFLAGS) -fPIC -DPIC
libdconf_libdbus_1_shared_a_SOURCES = $(libdconf_libdbus_1_a_SOURCES)

dconf_dbus_1includedir = $(includedir)/dconf-dbus-1
dconf_dbus_1include_HEADERS = dconf-dbus-1.h

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf-dbus-1.pc

shlibdir = $(libdir)
shlib_PROGRAMS = libdconf-dbus-1.so.0.0.0

libdconf_dbus_1_so_0_0_0_CFLAGS = $(dbus_CFLAGS) $(gio_CFLAGS) -fPIC -DPIC
libdconf_dbus_1_so_0_0_0_LDADD = \
	../engine/libdconf-engine-shared.a		\
	../common/libdconf-common-hidden.a		\
	./libdconf-libdbus-1-shared.a			\
	../gvdb/libgvdb-shared.a			\
	../shm/libdconf-shm-shared.a			\
	 $(dbus_LIBS)					\
	$(glib_LIBS)
libdconf_dbus_1_so_0_0_0_LDFLAGS = -shared -Wl,-soname=libdconf-dbus-1.so.0
libdconf_dbus_1_so_0_0_0_SOURCES = dconf-dbus-1.c

nodist_noinst_DATA = libdconf-dbus-1.so libdconf-dbus-1.so.0

libdconf-dbus-1.so.0 libdconf-dbus-1.so: libdconf-dbus-1.so.0.0.0
	$(AM_V_GEN) ln -fs libdconf-dbus-1.so.0.0.0 $@

install-data-hook:
	ln -fs libdconf-dbus-1.so.0.0.0 $(DESTDIR)$(shlibdir)/libdconf-dbus-1.so.0
	ln -fs libdconf-dbus-1.so.0.0.0 $(DESTDIR)$(shlibdir)/libdconf-dbus-1.so

uninstall-hook:
	rm -f $(DESTDIR)$(shlibdir)/libdconf-dbus-1.so.0
	rm -f $(DESTDIR)$(shlibdir)/libdconf-dbus-1.so

CLEANFILES = libdconf-dbus-1.so.0 libdconf-dbus-1.so
