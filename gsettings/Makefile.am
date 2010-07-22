AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings -fPIC -DPIC
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/gvdb -I$(top_srcdir)/engine $(gio_CFLAGS)

giomodules_PROGRAMS = libdconfsettings.so

libdconfsettings_so_LDADD = $(gio_LIBS)
libdconfsettings_so_LDFLAGS = -module -avoid-version -shared
libdconfsettings_so_SOURCES = \
	../engine/dconf-engine.c	\
	../common/dconf-shmdir.c	\
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
