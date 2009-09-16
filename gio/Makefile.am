AM_CFLAGS = -I$(top_srcdir)/dconf $(gio_CFLAGS) \
                -Wall -Wmissing-prototypes -Wwrite-strings

giomodules_LTLIBRARIES = libdconfsettings.la

libdconfsettings_la_LIBADD = ../dconf/libdconf.la $(gio_LIBS)
libdconfsettings_la_SOURCES = \
	dconfsettings.c		\
	dconfstorage.c

noinst_HEADERS = \
	dconfstorage.h
