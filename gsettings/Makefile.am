AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings
INCLUDES = -I$(top_srcdir)/{common,gvdb,engine} $(gio_CFLAGS)

giomodules_LTLIBRARIES = libdconfsettings.la

libdconfsettings_la_LIBADD = $(gio_LIBS)
libdconfsettings_la_LDFLAGS = -module -avoid-version -shared
libdconfsettings_la_SOURCES = \
	../engine/dconf-engine.c	\
	../gvdb/gvdb-reader.c		\
	dconfsettingsbackend.c

uninstall-hook:
	rm -f $(DESTDIR)$(giomodulesdir)/libdconfsettings.so
	if test -z "$(DESTDIR)" -a "$(gio_QUERYMODULES)" != "no" ; then \
	  $(gio_QUERYMODULES) $(giomodulesdir) ;  \
	fi

install-data-hook:
	rm -f $(DESTDIR)$(giomodulesdir)/libdconfsettings.la
	if test -z "$(DESTDIR)" -a "$(gio_QUERYMODULES)" != "no" ; then \
	  $(gio_QUERYMODULES) $(giomodulesdir) ;  \
	fi
