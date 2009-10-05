AM_CFLAGS = -I$(top_srcdir)/dconf $(glib_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g

bin_PROGRAMS = \
	dconf-get	\
	dconf-list	\
	dconf-lock	\
	dconf-reset	\
	dconf-set	\
	dconf-watch

dconf_get_LDADD = ../dconf/libdconf.la $(glib_LIBS)
dconf_list_LDADD = ../dconf/libdconf.la $(glib_LIBS)
dconf_lock_LDADD = ../dconf/libdconf.la $(glib_LIBS)
dconf_reset_LDADD = ../dconf/libdconf.la $(glib_LIBS)
dconf_set_LDADD = ../dconf/libdconf.la $(glib_LIBS)
dconf_watch_LDADD = ../dconf/libdconf.la $(glib_LIBS)
