include $(top_srcdir)/Makefile.gtester

noinst_LIBRARIES = libdconf-gdbus.a
INCLUDES = $(glib_CFLAGS) -I$(top_srcdir)/engine -I$(top_srcdir)/common
libdconf_gdbus_a_CFLAGS = -Wall -fPIC -DPIC
libdconf_gdbus_a_SOURCES = dconf-gdbus-thread.c
