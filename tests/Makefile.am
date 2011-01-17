AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/engine -I$(top_srcdir)/client $(gio_CFLAGS) -I$(top_srcdir)/dbus-1 $(dbus_CFLAGS)

noinst_PROGRAMS = paths gsettings dbus1

dbus1_LDFLAGS = -L../dbus-1 -ldconf-dbus-1 $(glib_LIBS)
gsettings_LDADD = $(gio_LIBS)
paths_LDADD = $(gio_LIBS)
paths_SOURCES = \
	../common/dconf-paths.c		\
	paths.c
