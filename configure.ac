AC_INIT(dconf, alpha)
AM_INIT_AUTOMAKE
AM_MAINTAINER_MODE

AC_PROG_LIBTOOL
AC_PROG_CC

PKG_CHECK_MODULES(gbus, gbus)
PKG_CHECK_MODULES(gtk, gtk+-2.0)

AC_OUTPUT([
  editor/Makefile
  service/Makefile
  dconf/Makefile
  dconf/dconf.pc
  tests/Makefile
  Makefile
])
