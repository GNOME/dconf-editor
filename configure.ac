AC_INIT([dconf],
        [0.5.2],
        [https://bugzilla.gnome.org/enter_bug.cgi?product=dconf],
        [dconf])

AC_CONFIG_SRCDIR([configure.ac])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([aux])

AM_INIT_AUTOMAKE([1.11 -Wno-portability])
AM_SILENT_RULES([yes])

# Check for programs
AC_PROG_CC
AM_PROG_VALAC([0.9.5])

# Introspection
GOBJECT_INTROSPECTION_CHECK([0.9.5])

# Gtk-doc support
GTK_DOC_CHECK([1.15])

# Dependencies
PKG_CHECK_MODULES(gio, gio-2.0 >= 2.25.16)

AC_MSG_CHECKING([which gtk+ version to compile against])
AC_ARG_WITH([gtk],
  [AS_HELP_STRING([--with-gtk=2.0|3.0],[which gtk+ version to compile against (default: 2.0)])],
  [case "$with_gtk" in
     2.0|3.0) ;;
     *) AC_MSG_ERROR([invalid gtk version specified]) ;;
   esac],
  [with_gtk=2.0])
AC_MSG_RESULT([$with_gtk])

case "$with_gtk" in
  2.0) GTK_API_VERSION=2.0
       GTK_REQUIRED=2.21.8
       ;;
  3.0) GTK_API_VERSION=3.0
       GTK_REQUIRED=2.90.7
       ;;
esac
AC_SUBST(GTK_API_VERSION)

AC_ARG_ENABLE(editor,
              AC_HELP_STRING([--disable-editor],
                             [Disable the dconf editor]))
AM_CONDITIONAL(ENABLE_EDITOR, test "x$enable_editor" != "xno")

if test "x$enable_editor" != "xno"; then
  PKG_CHECK_MODULES(gtk, gtk+-$GTK_API_VERSION >= $GTK_REQUIRED)
  PKG_CHECK_MODULES(libxml, libxml-2.0)
fi

AC_ARG_WITH(gio_modules_dir, [  --with-gio-modules-dir=PATH choose directory for the GIO module, [default=LIBDIR/gio/modules]], giomodulesdir="$withval", giomodulesdir=${libdir}/gio/modules)
AC_SUBST(giomodulesdir)

AC_ARG_WITH(dbus_service_dir, [  --with-dbus-service-dir=PATH choose directory for dbus service files, [default=PREFIX/share/dbus-1/services]], dbusservicedir="$withval", dbusservicedir=${datadir}/dbus-1/services)
AC_SUBST(dbusservicedir)

AC_ARG_WITH(dbus_system_service_dir, [  --with-dbus-system-service-dir=PATH choose directory for dbus system service files, [default=PREFIX/share/dbus-1/system-services]], dbussystemservicedir="$withval", dbussystemservicedir=${datadir}/dbus-1/system-services)
AC_SUBST(dbussystemservicedir)

AC_SUBST(dconfincludedir, ${includedir}/dconf)

AC_PATH_PROG(gio_QUERYMODULES, gio-querymodules, no)

AC_CONFIG_FILES([
  common/Makefile
  gvdb/Makefile
  engine/Makefile
  gsettings/Makefile
  client/dconf.pc
  client/Makefile
  service/Makefile
  bin/Makefile
  editor/Makefile
  tests/Makefile
  docs/Makefile
  Makefile
])
AC_OUTPUT
