project(
  'dconf-editor', ['c', 'vala'],
  version: '49.0',
  license: 'GPL3+',
  default_options: [
    'buildtype=debugoptimized',
    'warning_level=1'
  ],
  meson_version: '>= 0.59.0',
)

dconf_editor_name = meson.project_name()
dconf_editor_version = meson.project_version()

dconf_editor_prefix = get_option('prefix')
dconf_editor_bindir = join_paths(dconf_editor_prefix, get_option('bindir'))
dconf_editor_datadir = join_paths(dconf_editor_prefix, get_option('datadir'))
dconf_editor_localedir = join_paths(dconf_editor_prefix, get_option('localedir'))
dconf_editor_mandir = join_paths(dconf_editor_prefix, get_option('mandir'))

dconf_editor_pkgdatadir = join_paths(dconf_editor_datadir, dconf_editor_name)

dconf_editor_gettext = 'dconf-editor'
dconf_editor_namespace = 'ca.desrt.dconf-editor'

cc = meson.get_compiler('c')
valac = meson.get_compiler('vala')

vala_req_version = '>= 0.40.0'

assert(valac.version().version_compare(vala_req_version),
       'vala ' + vala_req_version + ' is required')

config_h = configuration_data()

# package
set_defines = [
  ['PACKAGE', dconf_editor_name],
  ['PACKAGE_BUGREPORT', 'https://bugzilla.gnome.org/enter_bug.cgi?product=' + dconf_editor_name],
  ['PACKAGE_NAME', dconf_editor_name],
  ['PACKAGE_STRING', '@0@ @1@'.format(dconf_editor_name, dconf_editor_version)],
  ['PACKAGE_TARNAME', dconf_editor_name],
  ['PACKAGE_URL', 'https://wiki.gnome.org/Apps/DconfEditor'],
  ['PACKAGE_VERSION', dconf_editor_version],
  ['VERSION', dconf_editor_version],
  # i18n
  ['GETTEXT_PACKAGE', dconf_editor_gettext]
]

foreach define: set_defines
  config_h.set_quoted(define[0], define[1])
endforeach

# headers
check_headers = [
  ['HAVE_DLFCN_H', 'dlfcn.h'],
  ['HAVE_FLOAT_H', 'float.h'],
  ['HAVE_INTTYPES_H', 'inttypes.h'],
  ['HAVE_MEMORY_H', 'memory.h'],
  ['HAVE_STDINT_H', 'stdint.h'],
  ['HAVE_STDLIB_H', 'stdlib.h'],
  ['HAVE_STRINGS_H', 'strings.h'],
  ['HAVE_STRING_H', 'string.h'],
  ['HAVE_SYS_STAT_H', 'sys/stat.h'],
  ['HAVE_UNISTD_H', 'unistd.h'],
  # i18n
  ['HAVE_LOCALE_H', 'locale.h']
]

foreach header: check_headers
  if cc.has_header(header[1])
    config_h.set(header[0], true)
  endif
endforeach

sys_types_h = cc.has_header('sys/types.h')
config_h.set('HAVE_SYS_TYPES_H', sys_types_h)
if not sys_types_h
  config_h.set('size_t', 'unsigned int')
endif

# functions
check_functions = [
  ['HAVE_MEMSET', 'memset'],
  ['HAVE_STRSTR', 'strstr'],
  # i18n
  ['HAVE_DCGETTEXT', 'dcgettext'],
  ['HAVE_GETTEXT', 'gettext'],
  ['HAVE_ICONV', 'iconv'],
  ['HAVE_SETLOCALE', 'setlocale']
]

if host_machine.system().contains('darwin')
  check_functions += [
    ['HAVE_CFLOCALECOPYCURRENT', 'CFLocaleCopyCurrent'],
    ['HAVE_CFPREFERENCESCOPYAPPVALUE', 'CFPreferencesCopyAppValue']
  ]
endif

foreach func: check_functions
  if cc.has_function(func[1])
    config_h.set(func[0], true)
  endif
endforeach

# compiler flags
add_project_arguments('-DHAVE_CONFIG_H', language: 'c')

gnome = import('gnome')
i18n = import('i18n')

po_dir = join_paths(meson.source_root(), 'po')

top_inc = include_directories('.')

subdir('editor')
subdir('po')

configure_file(
  output: 'config.h',
  configuration: config_h
)

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
