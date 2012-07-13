include $(top_srcdir)/Makefile.gtester

include gtk-doc.make

DOC_MODULE = dconf

DOC_MAIN_SGML_FILE = dconf-docs.xml

DOC_SOURCE_DIR = $(top_srcdir)/client $(top_srcdir)/common
HFILE_GLOB = $(top_srcdir)/client/*.h $(top_srcdir)/common/*.h
CFILE_GLOB = $(top_srcdir)/client/*.c $(top_srcdir)/common/*.c

MKDB_OPTIONS = --output-format=xml

INCLUDES = $(gio_CFLAGS)
GTKDOC_LIBS = $(gio_LIBS) -L../client -ldconf -Wl,-rpath=../client
