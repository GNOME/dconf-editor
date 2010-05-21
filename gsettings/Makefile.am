AM_CFLAGS = $(gio_CFLAGS) -I$(top_srcdir)/gvdb

giomodules_LTLIBRARIES = libdconfsettings.la

libdconfsettings_la_LIBADD = $(gio_LIBS)
libdconfsettings_la_LDFLAGS = -module -avoid-version -shared
libdconfsettings_la_SOURCES = \
	../gvdb/gvdb-reader.c	\
	dconfdatabase.h		\
	dconfdatabase.c		\
	dconfsettingsbackend.c

install-data-hook:
	rm -f $(giomodulesdir)/libdconfsettings.la
	if test -z "$(DESTDIR)" -a "$(gio_QUERYMODULES)" != "no" ; then \
	  $(gio_QUERYMODULES) $(giomodulesdir) ;  \
	fi
