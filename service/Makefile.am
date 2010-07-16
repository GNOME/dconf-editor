AM_CFLAGS = $(gio_CFLAGS) -I$(top_srcdir)/gvdb -Wall -Wmissing-prototypes -Wwrite-strings

libexec_PROGRAMS = dconf-service

dbussystemservice_DATA = ca.desrt.dconf.service
dbusservice_DATA = ca.desrt.dconf.service

dconf_service_LDADD = $(gio_LIBS)
dconf_service_SOURCES = \
	../gvdb/gvdb-builder.c	\
	../gvdb/gvdb-reader.c	\
	dconf-rebuilder.h	\
	dconf-rebuilder.h	\
	dconf-rebuilder.c	\
	dconf-writer.h		\
	dconf-writer.c		\
	service.c

DISTCLEANFILES = ca.desrt.dconf.service

ca.desrt.dconf.service: Makefile
	$(AM_V_GEN) echo -e '[D-BUS Service]\nName=ca.desrt.dconf\nExec=${libexecdir}/dconf-service' > $@
