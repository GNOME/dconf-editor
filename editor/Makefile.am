AM_CFLAGS = -I$(top_srcdir)/dconf $(gtk_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g
CFLAGS += -Wno-error

bin_PROGRAMS = dconf-editor

AM_VALAFLAGS = --pkg gtk+-2.0 --pkg dconf
dconf_editor_LDADD = $(gvariant_LIBS) $(gtk_LIBS) ../dconf/libdconf.la
dconf_editor_SOURCES = editor.vala
