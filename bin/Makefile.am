include $(top_srcdir)/Makefile.gtester

INCLUDES = -I$(top_srcdir) -I$(top_srcdir)/client

bin_PROGRAMS = dconf

dconf_VALAFLAGS = --vapidir ../client --pkg=gio-2.0 --pkg=posix --pkg=dconf

dconf_CFLAGS = \
	$(gio_CFLAGS)		\
	-w

dconf_LDADD = \
	../client/libdconf.so.1		\
	$(gio_LIBS)

dconf_SOURCES = \
	../gvdb/gvdb-builder.c	\
	gvdb.vapi		\
	dconf-update.vala	\
	dconf-dump.vala		\
	dconf.vala

completiondir = $(datadir)/bash-completion/completions
completion_DATA = completion/dconf
EXTRA_DIST = $(completion_DATA)
