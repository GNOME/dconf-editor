AM_CFLAGS = -I$(top_srcdir)/dconf $(glib_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g

bin_PROGRAMS = \
	dconf-watch	\
	dconf

dconf_watch_LDADD = ../dconf/libdconf.la $(glib_LIBS)
dconf_LDADD = ../dconf/libdconf.la $(glib_LIBS)
