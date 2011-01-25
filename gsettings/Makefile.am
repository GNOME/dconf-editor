AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings -fPIC -DPIC
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/gvdb -I$(top_srcdir)/engine $(gio_CFLAGS)

giomodules_PROGRAMS = libdconfsettings.so

libdconfsettings_so_LDADD = $(gio_LIBS)
libdconfsettings_so_LDFLAGS = -shared
libdconfsettings_so_SOURCES = \
	../engine/dconf-engine.c	\
	../common/dconf-shmdir.c	\
	../gvdb/gvdb-reader.c		\
	dconfcontext.h			\
	dconfcontext.c			\
	dconfsettingsbackend.c

uninstall-hook:
	if test -z "$(DESTDIR)" -a "$(gio_QUERYMODULES)" != "no" ; then \
	  $(gio_QUERYMODULES) $(giomodulesdir) ;  \
	fi

install-data-hook:
	if test -z "$(DESTDIR)" -a "$(gio_QUERYMODULES)" != "no" ; then \
	  $(gio_QUERYMODULES) $(giomodulesdir) ;  \
	fi
