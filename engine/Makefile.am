noinst_LIBRARIES = libdconf-engine.a

libdconf_engine_a_CFLAGS = -fPIC -DPIC -Wall
INCLUDES = $(glib_CFLAGS) -I../gvdb -I../common

libdconf_engine_a_SOURCES = \
	../gvdb/gvdb-reader.c		\
	dconf-engine-profile.h		\
	dconf-engine-profile.c		\
	dconf-engine-source.h		\
	dconf-engine-source-user.c	\
	dconf-engine-source-system.c	\
	dconf-engine-source.c		\
	dconf-engine.h			\
	dconf-engine.c
