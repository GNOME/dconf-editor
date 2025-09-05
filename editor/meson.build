desktop = dconf_editor_namespace + '.desktop'

i18n.merge_file (
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

appdata = dconf_editor_namespace + '.metainfo.xml'

appdata_file = i18n.merge_file(
  input: appdata + '.in',
  output: appdata,
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(dconf_editor_datadir, 'metainfo')
)

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test(
    'validate-appdata', appstreamcli,
    args: ['validate', '--no-net', '--explain', appdata_file.full_path()],
  )
endif

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
  'bookmarks-headerbar.vala',
  'bookmarks-list.vala',
  'bookmarks-view.vala',
  'bookmarks-window.vala',
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

css_data = files(
  'base-window.css',
  'dconf-editor.css',
  'large-pathbar.css'
)

ui_data = files(
  'adaptative-window.ui',
  'base-headerbar.ui',
  'base-view.ui',
  'base-window.ui',
  'bookmarks.ui',
  'bookmarks-controller.ui',
  'bookmark.ui',
  'browser-infobar.ui',
  'browser-stack.ui',
  'delayed-setting-view.ui',
  'filter-list-box-row.ui',
  'folder-list-box-row.ui',
  'help-overlay.ui',
  'key-list-box-row.ui',
  'large-pathbar-item.ui',
  'large-pathbar.ui',
  'modifications-revealer.ui',
  'notifications-revealer.ui',
  'overlayed-list.ui',
  'pathentry.ui',
  'pathwidget.ui',
  'property-row.ui',
  'registry-info.ui',
  'registry-list.ui',
  'registry-placeholder.ui',
  'return-list-box-row.ui',
  'search-list-box-row.ui',
  'short-pathbar.ui'
)

resource_data = css_data + ui_data

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
  dependency('libhandy-1', version: '>= 1.6'),
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
