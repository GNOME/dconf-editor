bin_PROGRAMS = dconf-editor

dconf_editor_VALAFLAGS = \
	--pkg posix \
	--pkg gio-2.0 \
	--pkg gtk+-3.0 \
	--pkg gmodule-2.0 \
	--pkg dconf \
	--gresources $(builddir)/dconf-editor.gresource.xml \
	--target-glib $(GLIB_REQUIRED)

dconf_editor_LDADD = $(DCONF_EDITOR_LIBS)

dconf_editor_CFLAGS = \
	-DPKGDATADIR=\"$(pkgdatadir)\" \
	-DVERSION=\"$(VERSION)\" \
	-DLOCALEDIR=\"$(localedir)\" \
	-DGETTEXT_PACKAGE=\"$(GETTEXT_PACKAGE)\" \
	-w \
	$(DCONF_EDITOR_CFLAGS)

resource_data = \
	dconf-editor.gresource.xml \
	dconf-editor-menu.ui \
	dconf-editor.css \
	dconf-editor.ui \
	folder-list-box-row.ui \
	key-list-box-row.ui \
	bookmarks.ui \
	bookmark.ui \
	help-overlay.ui \
	modifications-revealer.ui \
	pathbar.ui \
	pathbar-item.ui \
	property-row.ui \
	registry-info.ui \
	registry-view.ui

resources.c: $(resource_data)
	$(AM_V_GEN) $(GLIB_COMPILE_RESOURCES) --sourcedir=$(srcdir) --target=$@ --generate-source $<

nodist_dconf_editor_SOURCES = resources.c

dconf_editor_SOURCES = \
	config.vapi \
	dconf-editor.vala \
	dconf-window.vala \
	dconf-model.vala \
	dconf-view.vala \
	bookmarks.vala \
	key-list-box-row.vala \
	modifications-revealer.vala \
	pathbar.vala \
	registry-info.vala \
	registry-view.vala

desktopdir = $(datadir)/applications
desktop_in_files = ca.desrt.dconf-editor.desktop.in.in
desktop_DATA = $(desktop_in_files:.desktop.in.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

dbusservicedir = $(datadir)/dbus-1/services
dbusservice_DATA = ca.desrt.dconf-editor.service

ca.desrt.dconf-editor.service: Makefile
	$(AM_V_GEN) (echo '[D-BUS Service]'; \
	             echo 'Name=ca.desrt.dconf-editor'; \
	             echo 'Exec=${bindir}/dconf-editor --gapplication-service') > $@.tmp && \
	             mv $@.tmp $@

@APPSTREAM_XML_RULES@
appstream_in_files = ca.desrt.dconf-editor.appdata.xml.in
appstream_XML = $(appstream_in_files:.xml.in=.xml)
@INTLTOOL_XML_RULE@

%.appdata.valid: %.appdata.xml
	$(AM_V_GEN) if test -f "$<"; then d=; else d="$(srcdir)/"; fi; \
	            if test -n "$(APPSTREAM_UTIL)"; \
	                then $(APPSTREAM_UTIL) --nonet validate-relax $${d}$<; fi
check-am: $(appstream_XML:.appdata.xml=.appdata.valid)

gsettings_SCHEMAS = ca.desrt.dconf-editor.gschema.xml
@GSETTINGS_RULES@

nobase_data_DATA = $(icons)

icons = \
	icons/hicolor/16x16/apps/dconf-editor.png \
	icons/hicolor/22x22/apps/dconf-editor.png \
	icons/hicolor/24x24/apps/dconf-editor.png \
	icons/hicolor/32x32/apps/dconf-editor.png \
	icons/hicolor/48x48/apps/dconf-editor.png \
	icons/hicolor/64x64/apps/dconf-editor.png \
	icons/hicolor/256x256/apps/dconf-editor.png \
	icons/hicolor/scalable/apps/dconf-editor-symbolic.svg

install-data-hook: update-icon-cache
uninstall-hook: update-icon-cache
update-icon-cache:
	if test -z "$(DESTDIR)"; then \
		gtk-update-icon-cache -f -t $(datadir)/icons/hicolor; \
	fi

man_MANS = dconf-editor.1

CLEANFILES = $(appstream_XML) $(desktop_DATA) $(dbusservice_DATA) resources.c
EXTRA_DIST = $(appstream_in_files) $(gsettings_SCHEMAS) $(icons) $(resource_data) $(man_MANS)
