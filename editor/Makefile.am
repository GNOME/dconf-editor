AM_CFLAGS = -I$(top_srcdir)/dconf $(gtk_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g
CFLAGS += -Wno-error

bin_PROGRAMS = dconf-editor

dconf_editor_VALASOURCES = \
	editor.vala

DEFS =
BUILT_SOURCES = dconf-editor.vala.stamp

dconf_editor_LDADD = $(gvariant_LIBS) $(gtk_LIBS) ../dconf/libdconf.la
dconf_editor_SOURCES = \
	dconf-editor.vala.stamp			\
	$(dconf_editor_VALASOURCES:.vala=.c)	\
	$(dconf_editor_VALASOURCES:.vala=.h)


dconf-editor.vala.stamp: $(dconf_editor_VALASOURCES)
	valac -C --pkg gtk+-2.0 dconf.vapi $^
	touch $@

CLEANFILES = *.c *.h dconf-editor.vala.stamp
EXTRA_DIST = $(dconf_editor_VALASOURCES)
