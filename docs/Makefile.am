include $(top_srcdir)/Makefile.gtester

include gtk-doc.make

DOC_MODULE = dconf

DOC_MAIN_SGML_FILE = dconf-docs.xml

DOC_SOURCE_DIR = ../client ../common

MKDB_OPTIONS = --output-format=xml

INCLUDES = $(gio_CFLAGS)
GTKDOC_LIBS = $(gio_LIBS) -L../client -ldconf -Wl,-rpath=../client

IGNORE_HFILES = \
	dconf-engine.h		\
	dconf-shmdir.h		\
	dconf-resetlist.h	\
	dconf-readtype.h	\
	dconf-rebuilder.h	\
	gvdb-builder.h		\
	gvdb-reader.h		\
	gvdb-format.h


