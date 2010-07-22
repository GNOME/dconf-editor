include gtk-doc.make

DOC_MODULE = dconf

DOC_MAIN_SGML_FILE = dconf-docs.xml

DOC_SOURCE_DIR = ..

MKDB_OPTIONS = --output-format=xml

INCLUDES = $(gio_CFLAGS)
GTKDOC_LIBS = $(gio_LIBS) ../client/libdconf.so

IGNORE_HFILES = \
	dconf-engine.h		\
	dconf-resetlist.h	\
	dconf-readtype.h	\
	dconf-rebuilder.h	\
	gvdb-builder.h		\
	gvdb-reader.h		\
	gvdb-format.h


