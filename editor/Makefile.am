bin_PROGRAMS = dconf-editor

AM_CFLAGS = $(gtk_CFLAGS) $(gmodule_CFLAGS) $(libxml_CFLAGS) -I$(top_srcdir)/common -I$(top_srcdir)/client -DPKGDATADIR=\"@datadir@/dconf-editor\"
AM_VALAFLAGS = --vapidir ../client --pkg gtk+-3.0 --pkg gmodule-2.0 --pkg libxml-2.0 --pkg dconf
CFLAGS += -Wno-error -Wno-unused-but-set-variable -Wno-unused-variable
dconf_editor_LDADD = ../client/libdconf.so.0 $(gtk_LIBS) $(gmodule_LIBS) $(gee_LIBS) $(libxml_LIBS)
dconf_editor_SOURCES = config.vapi dconf-editor.vala dconf-model.vala dconf-schema.vala dconf-view.vala

desktopdir = $(datadir)/applications
desktop_in_files = dconf-editor.desktop.in.in
desktop_DATA = $(desktop_in_files:.desktop.in.in=.desktop)

gsettings_SCHEMAS = ca.desrt.dconf-editor.gschema.xml
@GSETTINGS_RULES@

uidir = $(datadir)/dconf-editor
dist_ui_DATA = dconf-editor.ui

EXTRA_DIST = $(gsettings_SCHEMAS)
