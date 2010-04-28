AM_CFLAGS = $(gio_CFLAGS) -I$(top_srcdir)/gvdb

giomodules_LTLIBRARIES = libdconfsettings.la

libdconfsettings_la_LIBADD = $(gio_LIBS)
libdconfsettings_la_SOURCES = \
	../gvdb/gvdb-reader.c	\
	dconfdatabase.h		\
	dconfdatabase.c		\
	dconfsettingsbackend.c

