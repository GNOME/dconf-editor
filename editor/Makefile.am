bin_PROGRAMS = dconf-editor

AM_CFLAGS = $(gtk_CFLAGS) $(libxml_CFLAGS) -I$(top_srcdir)/common -I$(top_srcdir)/client -DPKGDATADIR=\"@datadir@/dconf-editor\"
AM_VALAFLAGS = --vapidir ../client --pkg gtk+-3.0 --pkg libxml-2.0 --pkg dconf
CFLAGS += -Wno-error
dconf_editor_LDADD = ../client/libdconf.so.0 $(gtk_LIBS) $(gee_LIBS) $(libxml_LIBS)
dconf_editor_SOURCES = config.vapi dconf-editor.vala dconf-model.vala dconf-schema.vala dconf-view.vala

desktopdir = $(datadir)/applications
desktop_in_files = dconf-editor.desktop.in.in
desktop_DATA = $(desktop_in_files:.desktop.in.in=.desktop)

uidir = $(datadir)/dconf-editor
ui_DATA = dconf-editor.ui
