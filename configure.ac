AC_INIT([dconf-editor],[3.22.0],[https://bugzilla.gnome.org/enter_bug.cgi?product=dconf-editor],[dconf-editor])

AC_CONFIG_SRCDIR([configure.ac])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_HEADERS([config.h])

AM_INIT_AUTOMAKE([1.11.2 foreign -Wno-portability no-dist-gzip dist-xz])
AM_SILENT_RULES([yes])

# Set default CFLAGS before AC_PROG_CC does
if test "${CFLAGS+yes}" != "yes"; then
  CFLAGS='-O2 -g -Wall -Wwrite-strings -Wmissing-prototypes -fno-common'
fi

# Check for programs
AC_PROG_CC
AM_PROG_VALAC([0.33.1])

# Use GLib resources
AC_PATH_PROG(GLIB_COMPILE_RESOURCES, glib-compile-resources)

dnl requested by 'autoscan'

dnl editor/dconf-model.c:4466
AC_CHECK_FUNCS([memset])
dnl editor/dconf-editor.c:126
AC_CHECK_FUNCS([setlocale])
dnl editor/dconf-model.c:3550
AC_CHECK_FUNCS([strstr])
dnl editor/dconf-model.c:28
AC_CHECK_HEADERS([float.h])
dnl editor/dconf-editor.c:28
AC_CHECK_HEADERS([locale.h])
dnl editor/modifications-revealer.c:26
AC_CHECK_HEADERS([stdlib.h])
dnl editor/modifications-revealer.c:27
AC_CHECK_HEADERS([string.h])
dnl editor/key-list-box-row.c:2686
AC_TYPE_SIZE_T

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
