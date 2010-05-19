AC_INIT(dconf, 0.3)
AM_INIT_AUTOMAKE
AM_SILENT_RULES
AC_PROG_LIBTOOL
AC_PROG_CC

PKG_CHECK_MODULES(gio, gio-2.0 >= 2.25.6)

AC_ARG_WITH(gio_modules_dir, [  --with-gio-modules-dir=PATH choose directory for the GIO module, [default=LIBDIR/gio/modules]], giomodulesdir="$withval", giomodulesdir=${libdir}/gio/modules)
AC_SUBST(giomodulesdir)

AC_ARG_WITH(dbus_service_dir, [  --with-dbus-service-dir=PATH choose directory for dbus service files, [default=PREFIX/share/dbus-1/services]], dbusservicedir="$withval", dbusservicedir=${datadir}/dbus-1/services)
AC_SUBST(dbusservicedir)

AC_ARG_WITH(dbus_system_service_dir, [  --with-dbus-system-service-dir=PATH choose directory for dbus system service files, [default=PREFIX/share/dbus-1/system-services]], dbussystemservicedir="$withval", dbussystemservicedir=${datadir}/dbus-1/system-services)
AC_SUBST(dbussystemservicedir)

AC_OUTPUT([
  gsettings/Makefile
  service/Makefile
  gvdb/Makefile
  Makefile
])
