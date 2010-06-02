AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/engine -I$(top_srcdir)/client $(gio_CFLAGS)

noinst_PROGRAMS = paths

paths_LDADD = $(gio_LIBS)
paths_SOURCES = \
	../common/dconf-paths.c		\
	paths.c
