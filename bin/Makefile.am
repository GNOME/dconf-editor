AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings
CFLAGS += -Wno-error
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/engine -I$(top_srcdir)/client -I$(top_srcdir)/gvdb $(gio_CFLAGS)

bin_PROGRAMS = dconf

dconf_VALAFLAGS = --vapidir ../client --pkg=gio-2.0 --pkg=posix --pkg=dconf
dconf_LDADD = $(gio_LIBS) ../client/libdconf.so.0
dconf_SOURCES = dconf.vala dconf-update.vala ../gvdb/gvdb-builder.c gvdb.vapi fixes.vapi
