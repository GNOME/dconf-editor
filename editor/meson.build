desktop = dconf_editor_namespace + '.desktop'

i18n.merge_file (
  desktop,
  type: 'desktop',
  input: desktop + '.in',
  output: desktop,
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(dconf_editor_datadir, 'applications')
)

service_conf = configuration_data()
service_conf.set('bindir', dconf_editor_bindir)

service = dconf_editor_namespace + '.service'

configure_file(
  input: service + '.in',
  output: service,
  install: true,
  install_dir: join_paths(dconf_editor_datadir, 'dbus-1', 'services'),
  configuration: service_conf
)

appdata = dconf_editor_namespace + '.appdata.xml'

i18n.merge_file(
  appdata,
  input: appdata + '.in',
  output: appdata,
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(dconf_editor_datadir, 'metainfo')
)

install_data(
  dconf_editor_namespace + '.gschema.xml',
  install_dir: join_paths(dconf_editor_datadir, 'glib-2.0', 'schemas')
)

install_subdir(
  'icons',
  install_dir: dconf_editor_datadir
)

install_data(
  dconf_editor_name + '.1',
  install_dir: join_paths(dconf_editor_mandir, 'man1')
)

sources = files(
  'bookmarks.vala',
  'browser-view.vala',
  'dconf-editor.vala',
  'dconf-model.vala',
  'dconf-view.vala',
  'dconf-window.vala',
  'key-list-box-row.vala',
  'modifications-handler.vala',
  'modifications-revealer.vala',
  'pathbar.vala',
  'registry-info.vala',
  'registry-placeholder.vala',
  'registry-search.vala',
  'registry-view.vala'
)

resource_data = files(
  'bookmarks.ui',
  'bookmark.ui',
  'browser-view.ui',
  'dconf-editor.css',
  'dconf-editor-menu.ui',
  'dconf-editor.ui',
  'folder-list-box-row.ui',
  'help-overlay.ui',
  'key-list-box-row.ui',
  'modifications-revealer.ui',
  'pathbar-item.ui',
  'pathbar.ui',
  'property-row.ui',
  'registry-info.ui',
  'registry-placeholder.ui',
  'registry-search.ui',
  'registry-view.ui'
)

sources += gnome.compile_resources(
  'resources',
  dconf_editor_name + '.gresource.xml',
  dependencies: resource_data,
  export: true
)

deps = [
  dependency('dconf', version: '>= 0.25.1'),
  dependency('glib-2.0', version: '>= 2.46.0'),
  dependency('gmodule-2.0'),
  dependency('gtk+-3.0', version: '>= 3.22.0'),
  valac.find_library('config', dirs: meson.current_source_dir()),
  valac.find_library('posix')
]

cflags = [
  '-DPKGDATADIR="@0@"'.format(dconf_editor_pkgdatadir),
  '-DVERSION="@0@"'.format(dconf_editor_version),
  '-DLOCALEDIR="@0@"'.format(dconf_editor_localedir),
  '-DGETTEXT_PACKAGE="@0@"'.format(dconf_editor_gettext),
  '-DG_SETTINGS_ENABLE_BACKEND=1',
  '-w'
]

executable(
  dconf_editor_name,
  sources,
  include_directories: top_inc,
  dependencies: deps,
  c_args: cflags,
  vala_args: '--enable-experimental-non-null',
  install: true,
  install_dir: dconf_editor_bindir
)
