include $(top_srcdir)/Makefile.gtester

noinst_LIBRARIES = libdconf-gdbus.a
INCLUDES = $(glib_CFLAGS) -I../engine -I../common
libdconf_gdbus_a_CFLAGS = -Wall -fPIC -DPIC
libdconf_gdbus_a_SOURCES = dconf-gdbus-thread.c
