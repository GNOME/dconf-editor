AC_INIT([dconf],
        [0.9.0],
        [https://bugzilla.gnome.org/enter_bug.cgi?product=dconf],
        [dconf])

AC_CONFIG_SRCDIR([configure.ac])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([aux])
AC_CONFIG_HEADERS([config.h])

AM_INIT_AUTOMAKE([1.11 -Wno-portability no-dist-gzip dist-xz])
AM_SILENT_RULES([yes])

# Check for programs
AC_PROG_CC
AM_PROG_VALAC([0.11.7])

# Use GSettings
GLIB_GSETTINGS

# Gtk-doc support
GTK_DOC_CHECK([1.15])

# Dependencies
PKG_CHECK_MODULES(glib, glib-2.0 >= 2.27.2)
PKG_CHECK_MODULES(gio, gio-2.0)
PKG_CHECK_MODULES(dbus, dbus-1)

AC_ARG_ENABLE(editor,
              AC_HELP_STRING([--disable-editor],
                             [Disable the dconf editor]))
AM_CONDITIONAL(ENABLE_EDITOR, test "x$enable_editor" != "xno")

if test "x$enable_editor" != "xno"; then
  PKG_CHECK_MODULES(gtk, gtk+-3.0)
  PKG_CHECK_MODULES(gmodule, gmodule-2.0)
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
  dbus-1/dconf-dbus-1.pc
  client/dconf.pc
  client/Makefile
  service/Makefile
  dbus-1/Makefile
  bin/Makefile
  editor/Makefile
  editor/dconf-editor.desktop
  tests/Makefile
  docs/Makefile
  Makefile
])
AC_OUTPUT
