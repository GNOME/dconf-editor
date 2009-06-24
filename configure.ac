AC_INIT(dconf, alpha)
AM_INIT_AUTOMAKE
AM_MAINTAINER_MODE

AC_PROG_LIBTOOL
AC_PROG_CC


PKG_CHECK_MODULES(glib, glib-2.0)
PKG_CHECK_MODULES(dbus, dbus-1)
PKG_CHECK_MODULES(gtk, gtk+-2.0)

AC_OUTPUT([
  common/Makefile
  editor/Makefile
  writer/Makefile
  config/Makefile
  dconf/Makefile
  dconf/dconf.pc
  bin/Makefile
  Makefile
])
