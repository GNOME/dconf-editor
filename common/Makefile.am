include $(top_srcdir)/Makefile.gtester

dconfinclude_HEADERS = \
	dconf-paths.h

noinst_LIBRARIES = libdconf-common.a libdconf-common-shared.a
libdconf_common_a_CFLAGS = -Wall
INCLUDES = $(glib_CFLAGS)

libdconf_common_a_SOURCES = \
	dconf-changeset.h	\
	dconf-changeset.c	\
	dconf-paths.c

libdconf_common_shared_a_CFLAGS = -fPIC -DPIC $(libdconf_common_a_CFLAGS)
libdconf_common_shared_a_SOURCES = $(libdconf_common_a_SOURCES)
