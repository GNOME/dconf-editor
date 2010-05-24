AM_CFLAGS = -std=c89 -Wall -Wmissing-prototypes -Wwrite-strings
INCLUDES = -I$(top_srcdir)/{common,engine,client} $(gio_CFLAGS)

bin_PROGRAMS = dconf

dconf_LDADD = ../client/libdconf.la
