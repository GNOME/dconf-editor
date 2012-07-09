include $(top_srcdir)/Makefile.gtester

libexec_PROGRAMS = dconf-service

dbusservice_DATA = ca.desrt.dconf.service

dconf_service_CFLAGS = $(gio_CFLAGS)
dconf_service_LDADD = \
	../common/libdconf-common.a	\
	../gvdb/libgvdb.a		\
	../shm/libdconf-shm.a		\
	$(gio_LIBS)

dconf_service_SOURCES = \
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
