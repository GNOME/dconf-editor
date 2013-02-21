include $(top_srcdir)/Makefile.gtester

noinst_LIBRARIES = libdconf-shm.a libdconf-shm-shared.a

libdconf_shm_a_CFLAGS = $(glib_CFLAGS) -DG_LOG_DOMAIN=\"dconf\"
libdconf_shm_a_SOURCES = \
	dconf-shm.h		\
	dconf-shm.c

libdconf_shm_shared_a_CFLAGS = $(libdconf_shm_a_CFLAGS) -fPIC -DPIC
libdconf_shm_shared_a_SOURCES = $(libdconf_shm_a_SOURCES)
