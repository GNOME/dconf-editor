bin_PROGRAMS = dconf-editor

AM_CFLAGS = $(gtk_CFLAGS) $(libxml_CFLAGS) -I$(top_srcdir)/common -I$(top_srcdir)/client 
AM_VALAFLAGS = --vapidir ../client --pkg gtk+-$(GTK_API_VERSION) --pkg libxml-2.0 --pkg dconf -D GTK$(GTK_API_VERSION:.0=)
CFLAGS += -Wno-error
dconf_editor_LDADD = ../client/libdconf.so.0 $(gtk_LIBS) $(gee_LIBS) $(libxml_LIBS)
dconf_editor_SOURCES = dconf-editor.vala dconf-model.vala dconf-schema.vala dconf-view.vala
