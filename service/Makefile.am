AM_CFLAGS = -I$(top_srcdir)/common $(glib_CFLAGS) $(dbus_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g

noinst_LIBRARIES = libdconf-service.a

libdconf_service_a_SOURCES = \
	dconf-writer.c		\
	dconf-writer-merge.c	\
	dconf-service.c

noinst_HEADERS = \
	dconf-writer-private.h	\
	dconf-writer.h		\
	dconf-service.h

noinst_PROGRAMS = dconf-service
dconf_service_LDADD = $(glib_LIBS) $(dbus_LIBS) libdconf-service.a
dconf_service_SOURCES = dconf-dbus-service.c
