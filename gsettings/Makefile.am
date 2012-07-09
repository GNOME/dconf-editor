include $(top_srcdir)/Makefile.gtester

giomodules_PROGRAMS = libdconfsettings.so

libdconfsettings_so_LDADD = \
	../engine/libdconf-engine-shared.a		\
	../gvdb/libgvdb-shared.a			\
	../gdbus/libdconf-gdbus-thread-shared.a		\
	../common/libdconf-common-shared.a		\
	../shm/libdconf-shm-shared.a			\
	$(gio_LIBS)

libdconfsettings_so_CFLAGS = $(gio_CFLAGS) -fPIC -DPIC
libdconfsettings_so_LDFLAGS = -shared
libdconfsettings_so_SOURCES = \
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
