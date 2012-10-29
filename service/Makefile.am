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
	$(BUILT_SOURCES)		\
	dconf-blame.c			\
	dconf-blame.h			\
	dconf-service.c			\
	dconf-service.h			\
	dconf-writer.h			\
	dconf-writer.c			\
	main.c

dconf-generated.c: dconf-generated.h

dconf-generated.h: ca.desrt.dconf.xml Makefile
	gdbus-codegen --generate-c-code dconf-generated --c-namespace DConfDBus --interface-prefix=ca.desrt.dconf. $(srcdir)/ca.desrt.dconf.xml

DISTCLEANFILES = ca.desrt.dconf.service

BUILT_SOURCES = dconf-generated.c dconf-generated.h

ca.desrt.dconf.service: Makefile
	$(AM_V_GEN) (echo '[D-BUS Service]'; \
	             echo 'Name=ca.desrt.dconf'; \
	             echo 'Exec=${libexecdir}/dconf-service') > $@.tmp && \
	            mv $@.tmp $@
