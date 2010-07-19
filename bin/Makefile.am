AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/engine -I$(top_srcdir)/client -I$(top_srcdir)/gvdb $(gio_CFLAGS)

bin_PROGRAMS = dconf dconf-update

dconf_LDADD = ../client/libdconf.la $(gio_LIBS)

dconf_update_VALAFLAGS = --pkg=posix --pkg=gio-2.0
dconf_update_LDADD = $(gio_LIBS)
dconf_update_SOURCES = dconf-update.vala ../gvdb/gvdb-builder.c gvdb.vapi fixes.vapi

dconf_VALAFLAGS = --pkg=gio-2.0 ../client/dconf.vapi
dconf_LDADD = $(gio_LIBS) ../client/libdconf.la
dconf_SOURCES = dconf.vala
