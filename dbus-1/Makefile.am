AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings -fPIC -DPIC
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/gvdb -I$(top_srcdir)/engine $(dbus_CFLAGS) $(glib_CFLAGS)

dconf_dbus_1includedir = $(includedir)/dconf-dbus-1
dconf_dbus_1include_HEADERS = dconf-dbus-1.h

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = dconf-dbus-1.pc

shlibdir = $(libdir)
shlib_PROGRAMS = libdconf-dbus-1.so.0.0.0

libdconf_dbus_1_so_0_0_0_LDADD = $(glib_LIBS) $(dbus_LIBS)
libdconf_dbus_1_so_0_0_0_LDFLAGS = -module -avoid-version -shared
libdconf_dbus_1_so_0_0_0_SOURCES = \
	../engine/dconf-engine.c	\
	../common/dconf-shmdir.c	\
	../gvdb/gvdb-reader.c		\
	dconf-dbus-1.c

noinst_DATA = libdconf-dbus-1.so libdconf-dbus-1.so.0

libdconf-dbus-1.so.0 libdconf-dbus-1.so: libdconf-dbus-1.so.0.0.0
	$(AM_V_GEN) ln -fs libdconf-dbus-1.so.0.0.0 $@

install-data-hook:
	ln -fs libdconf-dbus-1.so.0.0.0 $(DESTDIR)$(shlibdir)/libdconf-dbus-1.so.0
	ln -fs libdconf-dbus-1.so.0.0.0 $(DESTDIR)$(shlibdir)/libdconf-dbus-1.so

uninstall-hook:
	rm -f $(DESTDIR)$(shlibdir)/libdconf-dbus-1.so.0
	rm -f $(DESTDIR)$(shlibdir)/libdconf-dbus-1.so

