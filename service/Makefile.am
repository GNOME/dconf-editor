AM_CFLAGS = $(gio_CFLAGS) -I$(top_srcdir)/gvdb -I$(top_srcdir)/common -Wall -Wmissing-prototypes -Wwrite-strings

libexec_PROGRAMS = dconf-service

dbusservice_DATA = ca.desrt.dconf.service

dconf_service_LDADD = $(gio_LIBS)
dconf_service_SOURCES = \
	../gvdb/gvdb-builder.c		\
	../gvdb/gvdb-reader.c		\
	../common/dconf-shmdir.c	\
	dconf-interfaces.h		\
	dconf-interfaces.c		\
	dconf-rebuilder.h		\
	dconf-rebuilder.c		\
	dconf-writer.h			\
	dconf-writer.c			\
	dconf-state.h			\
	dconf-state.c			\
	service.c

DISTCLEANFILES = ca.desrt.dconf.service

ca.desrt.dconf.service: Makefile
	$(AM_V_GEN) (echo '[D-BUS Service]'; \
	             echo 'Name=ca.desrt.dconf'; \
	             echo 'Exec=${libexecdir}/dconf-service') > $@.tmp && \
	            mv $@.tmp $@
