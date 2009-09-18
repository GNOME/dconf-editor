AC_INIT(dconf, 0.1.2)
AM_INIT_AUTOMAKE
AM_MAINTAINER_MODE
AM_SILENT_RULES

AC_PROG_LIBTOOL
AC_PROG_CC

PKG_CHECK_MODULES(glib, glib-2.0)
PKG_CHECK_MODULES(dbus, dbus-1)

AC_ARG_ENABLE(gio,
              AS_HELP_STRING([--enable-gio],
                             [Enable dconf backend for GIO]),
              [], [
                if ${PKG_CONFIG} --exists gio-2.0; then
                  enable_gio=yes
                else
                  enable_gio=no
                fi
              ])

if test "$enable_gio" = "yes"; then
  PKG_CHECK_MODULES(gio, gio-2.0)

  giomodulesdir=`pkg-config --variable=giomoduledir gio-2.0`
  AC_SUBST(giomodulesdir)
fi

AM_CONDITIONAL(ENABLE_GIO, test "$enable_gio" = "yes")
AC_DEFINE(ENABLE_GIO)

AC_ARG_WITH(dbus_service_dir, [  --with-dbus-service-dir=PATH choose directory for dbus service files, [default=PREFIX/share/dbus-1/services]], dbusservicedir="$withval", dbusservicedir=${datadir}/dbus-1/services)
AC_SUBST(dbusservicedir)

AC_ARG_WITH(dbus_system_service_dir, [  --with-dbus-system-service-dir=PATH choose directory for dbus system service files, [default=PREFIX/share/dbus-1/system-services]], dbussystemservicedir="$withval", dbussystemservicedir=${datadir}/dbus-1/system-services)
AC_SUBST(dbussystemservicedir)

AC_OUTPUT([
  service/Makefile
  common/Makefile
  writer/Makefile
  config/Makefile
  dconf/Makefile
  dconf/dconf.pc
  bin/Makefile
  gio/Makefile
  Makefile
])
