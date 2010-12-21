AC_INIT([dconf],
        [0.6],
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

# Gtk-doc support
GTK_DOC_CHECK([1.15])

# Dependencies
PKG_CHECK_MODULES(gio, gio-2.0 >= 2.25.16)


AC_ARG_ENABLE(editor,
              AC_HELP_STRING([--disable-editor],
                             [Disable the dconf editor]))
AM_CONDITIONAL(ENABLE_EDITOR, test "x$enable_editor" != "xno")

if test "x$enable_editor" != "xno"; then
  PKG_CHECK_MODULES(gtk, gtk+-3.0)
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
