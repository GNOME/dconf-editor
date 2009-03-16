noinst_PROGRAMS = dconf-service

AM_CFLAGS = -I.. $(glib_CFLAGS) $(gbus_CFLAGS) -Wall

dconf_service_LDADD = $(glib_LIBS) $(gbus_LIBS)
dconf_service_SOURCES = dconf-writer.c service.c
