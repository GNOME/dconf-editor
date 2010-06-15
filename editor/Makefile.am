bin_PROGRAMS = dconf-editor

AM_CFLAGS = $(gtk_CFLAGS) $(gee_CFLAGS) $(libxml_CFLAGS) -I$(top_srcdir)/common -I$(top_srcdir)/client
AM_VALAFLAGS = --pkg gee-1.0 --pkg gtk+-2.0 --pkg libxml-2.0
dconf_editor_LDADD = ../client/libdconf.la $(gtk_LIBS) $(gee_LIBS) $(libxml_LIBS)
dconf_editor_SOURCES = dconf-editor.vala dconf-model.vala dconf-schema.vala dconf-view.vala dconf.vapi
