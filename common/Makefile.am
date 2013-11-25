include $(top_srcdir)/Makefile.gtester

dconfcommonincludedir = $(dconfincludedir)/common
dconfcommoninclude_HEADERS = \
	dconf-changeset.h	\
	dconf-error.h		\
	dconf-paths.h

noinst_LIBRARIES = libdconf-common.a libdconf-common-shared.a libdconf-common-hidden.a

libdconf_common_a_CFLAGS = $(glib_CFLAGS) -DG_LOG_DOMAIN=\"dconf\"
libdconf_common_a_SOURCES = \
	dconf-changeset.c	\
	dconf-error.c		\
	dconf-paths.c

libdconf_common_shared_a_CFLAGS = $(libdconf_common_a_CFLAGS) -fPIC -DPIC
libdconf_common_shared_a_SOURCES = $(libdconf_common_a_SOURCES)

libdconf_common_hidden_a_CFLAGS = $(libdconf_common_a_CFLAGS) -fPIC -DPIC -fvisibility=hidden
libdconf_common_hidden_a_SOURCES = $(libdconf_common_a_SOURCES)
