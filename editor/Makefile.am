include $(top_srcdir)/Makefile.gtester

INCLUDES = -I$(top_srcdir) -I$(top_srcdir)/client

bin_PROGRAMS = dconf-editor

dconf_editor_VALAFLAGS = --vapidir ../client --pkg gtk+-3.0 --pkg gmodule-2.0 --pkg libxml-2.0 --pkg dconf

dconf_editor_LDADD = \
	../client/libdconf.so.1		\
	$(gtk_LIBS)			\
	$(gee_LIBS)			\
	$(gmodule_LIBS)			\
	$(libxml_LIBS)

dconf_editor_CFLAGS = \
	$(gtk_CFLAGS)				\
	$(gee_CFLAGS)				\
	$(libxml_CFLAGS)			\
	-DPKGDATADIR=\"$(pkgdatadir)\"		\
	-DVERSION=\"$(VERSION)\"		\
	-DLOCALEDIR=\"$(localedir)\"		\
	-DGETTEXT_PACKAGE=\"$(GETTEXT_PACKAGE)\"\
	-w

dconf_editor_SOURCES = \
	config.vapi		\
	dconf-editor.vala	\
	dconf-model.vala	\
	dconf-schema.vala	\
	dconf-view.vala

desktopdir = $(datadir)/applications
desktop_in_files = dconf-editor.desktop.in.in
desktop_DATA = $(desktop_in_files:.desktop.in.in=.desktop)
CLEANFILES = $(desktop_DATA)
@INTLTOOL_DESKTOP_RULE@

gsettings_SCHEMAS = ca.desrt.dconf-editor.gschema.xml
@GSETTINGS_RULES@

nobase_data_DATA = $(icons)

icons = \
	icons/HighContrast/16x16/apps/dconf-editor.png		\
	icons/HighContrast/22x22/apps/dconf-editor.png		\
	icons/HighContrast/24x24/apps/dconf-editor.png		\
	icons/HighContrast/32x32/apps/dconf-editor.png		\
	icons/HighContrast/48x48/apps/dconf-editor.png		\
	icons/HighContrast/256x256/apps/dconf-editor.png	\
	icons/hicolor/16x16/apps/dconf-editor.png		\
	icons/hicolor/22x22/apps/dconf-editor.png		\
	icons/hicolor/24x24/apps/dconf-editor.png		\
	icons/hicolor/32x32/apps/dconf-editor.png		\
	icons/hicolor/48x48/apps/dconf-editor.png		\
	icons/hicolor/64x64/apps/dconf-editor.png		\
	icons/hicolor/256x256/apps/dconf-editor.png

install-data-hook: update-icon-cache
uninstall-hook: update-icon-cache
update-icon-cache:
	if test -z "$(DESTDIR)"; then \
		gtk-update-icon-cache -f -t $(datadir)/icons/HighContrast; \
		gtk-update-icon-cache -f -t $(datadir)/icons/hicolor; \
	fi

pkgdatadir = $(datadir)/dconf-editor
dist_pkgdata_DATA = dconf-editor.ui dconf-editor-menu.ui

EXTRA_DIST = $(gsettings_SCHEMAS) $(icons)
