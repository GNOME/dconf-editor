AC_PREREQ([2.69])
AC_INIT([dconf-editor],[3.26.2],[https://bugzilla.gnome.org/enter_bug.cgi?product=dconf-editor],[dconf-editor])

# might be config.h.in
AC_CONFIG_SRCDIR([configure.ac])

AC_CONFIG_HEADERS([config.h])
AC_CONFIG_MACRO_DIR([m4])

AM_INIT_AUTOMAKE([1.11.2 foreign -Wno-portability no-dist-gzip dist-xz])
AM_SILENT_RULES([yes])

# Check for programs
AC_PROG_CC
AC_PROG_INSTALL
AM_PROG_VALAC([0.33.1])

# Use GLib resources
AC_PATH_PROG(GLIB_COMPILE_RESOURCES, glib-compile-resources)

# Checks for header files.
# editor/dconf-model.c:28
# editor/dconf-editor.c:28
# editor/modifications-revealer.c:26
# editor/modifications-revealer.c:27
AC_CHECK_HEADERS([float.h locale.h stdlib.h string.h])

# Checks for typedefs, structures, and compiler characteristics.
# editor/key-list-box-row.c:2686
AC_TYPE_SIZE_T

# Checks for library functions.
# editor/dconf-model.c:4466
# editor/dconf-editor.c:126
# editor/dconf-model.c:3550
AC_CHECK_FUNCS([memset setlocale strstr])

# Use GSettings
GLIB_GSETTINGS

# Use AppStream
APPSTREAM_XML

# Dependencies
DCONF_REQUIRED=0.25.1
GLIB_REQUIRED=2.46.0
GTK_REQUIRED=3.22.0

PKG_CHECK_MODULES(DCONF_EDITOR, [
  glib-2.0 >= $GLIB_REQUIRED
  gtk+-3.0 >= $GTK_REQUIRED
  dconf >= $DCONF_REQUIRED
  gmodule-2.0
])

AC_SUBST([GLIB_REQUIRED])

dnl Gettext support
GETTEXT_PACKAGE=dconf
AC_SUBST(GETTEXT_PACKAGE)
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE, ["$GETTEXT_PACKAGE"], [Define the gettext package to be used])

AM_GNU_GETTEXT([external])
AM_GNU_GETTEXT_VERSION([0.19.7])

AC_CONFIG_FILES([
  editor/Makefile
  po/Makefile.in
  Makefile
])
AC_OUTPUT
