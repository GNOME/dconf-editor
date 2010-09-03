bin_PROGRAMS = dconf-editor

AM_CFLAGS = $(gtk_CFLAGS) $(libxml_CFLAGS) -I$(top_srcdir)/common -I$(top_srcdir)/client
AM_VALAFLAGS = --vapidir ../client --pkg gtk+-2.0 --pkg libxml-2.0 --pkg dconf
dconf_editor_LDADD = ../client/libdconf.so.0 $(gtk_LIBS) $(gee_LIBS) $(libxml_LIBS)
dconf_editor_SOURCES = dconf-editor.vala dconf-model.vala dconf-schema.vala dconf-view.vala
