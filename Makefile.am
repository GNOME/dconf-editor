ACLOCAL_AMFLAGS = -I m4 ${ACLOCAL_FLAGS}

SUBDIRS = gvdb service gsettings tests client bin engine common docs

if ENABLE_EDITOR
SUBDIRS += editor
endif

DISTCHECK_CONFIGURE_FLAGS = --enable-gtk-doc
