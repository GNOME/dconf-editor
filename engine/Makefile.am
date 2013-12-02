include $(top_srcdir)/Makefile.gtester

noinst_LIBRARIES = libdconf-engine.a libdconf-engine-shared.a

libdconf_engine_a_CFLAGS = $(glib_CFLAGS) -DG_LOG_DOMAIN=\"dconf\"
libdconf_engine_a_SOURCES = \
	dconf-engine-profile.h		\
	dconf-engine-profile.c		\
	dconf-engine-source-private.h	\
	dconf-engine-source.h		\
	dconf-engine-source-file.c	\
	dconf-engine-source-user.c	\
	dconf-engine-source-service.c	\
	dconf-engine-source-system.c	\
	dconf-engine-source.c		\
	dconf-engine.h			\
	dconf-engine.c

libdconf_engine_shared_a_CFLAGS = $(libdconf_engine_a_CFLAGS) -fPIC -DPIC
libdconf_engine_shared_a_SOURCES = $(libdconf_engine_a_SOURCES)
