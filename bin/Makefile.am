AM_CFLAGS = -I$(top_srcdir)/dconf $(glib_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g

bin_PROGRAMS = dconf-get dconf-list dconf-set dconf-watch

dconf_get_LDADD = ../dconf/libdconf.la
dconf_list_LDADD = ../dconf/libdconf.la
dconf_set_LDADD = ../dconf/libdconf.la
dconf_watch_LDADD = ../dconf/libdconf.la
