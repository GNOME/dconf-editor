AC_INIT(dconf, 0.4)
AM_INIT_AUTOMAKE
AM_SILENT_RULES(yes)
GOBJECT_INTROSPECTION_CHECK([0.6.7])
AC_PROG_LIBTOOL
AM_PROG_VALAC
GTK_DOC_CHECK
AC_PROG_CC

PKG_CHECK_MODULES(gio, gio-2.0 >= 2.25.7)
PKG_CHECK_MODULES(gtk, gtk+-2.0)

AC_ARG_WITH(gio_modules_dir, [  --with-gio-modules-dir=PATH choose directory for the GIO module, [default=LIBDIR/gio/modules]], giomodulesdir="$withval", giomodulesdir=${libdir}/gio/modules)
AC_SUBST(giomodulesdir)

AC_ARG_WITH(dbus_service_dir, [  --with-dbus-service-dir=PATH choose directory for dbus service files, [default=PREFIX/share/dbus-1/services]], dbusservicedir="$withval", dbusservicedir=${datadir}/dbus-1/services)
AC_SUBST(dbusservicedir)

AC_ARG_WITH(dbus_system_service_dir, [  --with-dbus-system-service-dir=PATH choose directory for dbus system service files, [default=PREFIX/share/dbus-1/system-services]], dbussystemservicedir="$withval", dbussystemservicedir=${datadir}/dbus-1/system-services)
AC_SUBST(dbussystemservicedir)

AC_SUBST(dconfincludedir, ${includedir}/dconf)

AC_PATH_PROG(gio_QUERYMODULES, gio-querymodules, no)

AC_OUTPUT([
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
