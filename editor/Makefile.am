AM_CFLAGS = -I.. $(gvariant_CFLAGS) $(gtk_CFLAGS)

noinst_PROGRAMS = editor

editor_VALASOURCES = \
	editor.vala

BUILT_SOURCES = editor.vala.stamp

editor_LDADD = $(gvariant_LIBS) $(gtk_LIBS) ../dconf/libdconf.la
editor_SOURCES = \
	editor.vala.stamp		\
	$(editor_VALASOURCES:.vala=.c)	\
	$(editor_VALASOURCES:.vala=.h)


editor.vala.stamp: $(editor_VALASOURCES)
	valac -C --pkg gtk+-2.0 dconf.vapi $^
	touch $@

CLEANFILES = *.c *.h editor.vala.stamp
