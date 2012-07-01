ACLOCAL_AMFLAGS = -I m4 ${ACLOCAL_FLAGS}

SUBDIRS = gvdb common service gsettings dbus-1 tests client bin engine docs

if ENABLE_EDITOR
SUBDIRS += editor
endif

DISTCHECK_CONFIGURE_FLAGS = --enable-gtk-doc
