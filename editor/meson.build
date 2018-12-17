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

gschema = dconf_editor_namespace + '.gschema.xml'
dconf_editor_schemadir = join_paths(dconf_editor_datadir, 'glib-2.0', 'schemas')
install_data(
  gschema,
  install_dir: dconf_editor_schemadir
)

xmllint = find_program('xmllint', required : false)
if xmllint.found()
  test('test_dtd', xmllint, args: ['--valid',
                                   '--noout', '--nowarning',
                                   join_paths(meson.current_source_dir(), gschema)])
else
  message('xmllint not found, no gschema DTD verification')
endif

install_subdir(
  'icons',
  install_dir: dconf_editor_datadir
)

install_data(
  dconf_editor_name + '.1',
  install_dir: join_paths(dconf_editor_mandir, 'man1')
)

install_data(
  'completion/dconf-editor',
  install_dir: join_paths(dconf_editor_datadir, 'bash-completion', 'completions')
)

sources = files(
  'about-list.vala',
  'adaptative-pathbar.vala',
  'adaptative-window.vala',
  'base-headerbar.vala',
  'base-view.vala',
  'base-window.vala',
  'bookmarks.vala',
  'bookmarks-controller.vala',
  'bookmarks-list.vala',
  'browser-content.vala',
  'browser-headerbar.vala',
  'browser-infobar.vala',
  'browser-stack.vala',
  'browser-view.vala',
  'browser-window.vala',
  'dconf-editor.vala',
  'dconf-headerbar.vala',
  'dconf-model.vala',
  'dconf-view.vala',
  'dconf-window.vala',
  'delayed-setting-view.vala',
  'key-editor-child.vala',
  'key-list-box-row.vala',
  'large-pathbar.vala',
  'model-utils.vala',
  'modifications-handler.vala',
  'modifications-list.vala',
  'modifications-revealer.vala',
  'night-light-monitor.vala',
  'notifications-revealer.vala',
  'overlayed-list.vala',
  'pathentry.vala',
  'pathwidget.vala',
  'registry-info.vala',
  'registry-list.vala',
  'registry-placeholder.vala',
  'registry-search.vala',
  'registry-view.vala',
  'schemas-utility.vala',
  'setting-object.vala',
  'short-pathbar.vala',
  'source-manager.vala'
)

resource_data = files(
  'base-headerbar.ui',
  'base-view.ui',
  'base-window.ui',
  'bookmarks.ui',
  'bookmarks-controller.ui',
  'bookmark.ui',
  'browser-infobar.ui',
  'browser-stack.ui',
  'config-list-box-row.ui',
  'dconf-editor.css',
  'delayed-setting-view.ui',
  'folder-list-box-row.ui',
  'help-overlay.ui',
  'key-list-box-row.ui',
  'large-pathbar-item.ui',
  'large-pathbar.css',
  'large-pathbar.ui',
  'modifications-revealer.ui',
  'notifications-revealer.ui',
  'overlayed-list.ui',
  'pathentry.ui',
  'pathwidget.ui',
  'property-row.ui',
  'registry-info.ui',
  'registry-placeholder.ui',
  'registry-view.ui',
  'return-list-box-row.ui',
  'search-list-box-row.ui',
  'short-pathbar.ui'
)

sources += gnome.compile_resources(
  'resources',
  dconf_editor_name + '.gresource.xml',
  dependencies: resource_data,
  export: true
)

deps = [
  dependency('dconf', version: '>= 0.26.1'),
  dependency('glib-2.0', version: '>= 2.56.0'),
  dependency('gmodule-2.0'),
  dependency('gtk+-3.0', version: '>= 3.22.27'),
  valac.find_library('config', dirs: meson.current_source_dir()),
  valac.find_library('posix')
]

cflags = [
  '-DPKGDATADIR="@0@"'.format(dconf_editor_pkgdatadir),
  '-DVERSION="@0@"'.format(dconf_editor_version),
  '-DLOCALEDIR="@0@"'.format(dconf_editor_localedir),
  '-DGETTEXT_PACKAGE="@0@"'.format(dconf_editor_gettext),
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
