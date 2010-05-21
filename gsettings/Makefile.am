AM_CFLAGS = $(gio_CFLAGS) -I$(top_srcdir)

giomodules_LTLIBRARIES = libdconfsettings.la

libdconfsettings_la_LIBADD = $(gio_LIBS)
libdconfsettings_la_LDFLAGS = -module -avoid-version -shared
libdconfsettings_la_SOURCES = \
	../engine/dconf-engine.h\
	../engine/dconf-engine.c\
	../gvdb/gvdb-reader.c	\
	dconfsettingsbackend.c

install-data-hook:
	rm -f $(DESTDIR)$(giomodulesdir)/libdconfsettings.la
	if test -z "$(DESTDIR)" -a "$(gio_QUERYMODULES)" != "no" ; then \
	  $(gio_QUERYMODULES) $(giomodulesdir) ;  \
	fi
