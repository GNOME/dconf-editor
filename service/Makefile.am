AM_CFLAGS = -I.. $(glib_CFLAGS) $(dbus_CFLAGS) -Wall

noinst_LIBRARIES = libdconf-service.a

libdconf_service_a_SOURCES = \
	dconf-writer.c		\
	dconf-writer-merge.c	\
	dconf-service.c

noinst_PROGRAMS = dconf-service
dconf_service_LDADD = $(glib_LIBS) $(dbus_LIBS) libdconf-service.a
dconf_service_SOURCES = dconf-dbus-service.c
