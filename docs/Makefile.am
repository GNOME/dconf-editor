include $(top_srcdir)/Makefile.gtester

include gtk-doc.make

DOC_MODULE = dconf

DOC_MAIN_SGML_FILE = dconf-docs.xml

DOC_SOURCE_DIR = $(top_srcdir)/client $(top_srcdir)/common
HFILE_GLOB = $(top_srcdir)/client/*.h $(top_srcdir)/common/*.h
CFILE_GLOB = $(top_srcdir)/client/*.c $(top_srcdir)/common/*.c

MKDB_OPTIONS = --output-format=xml

AM_CPPFLAGS = $(gio_CFLAGS)
GTKDOC_LIBS = $(gio_LIBS) -L../client -ldconf -Wl,-rpath=../client

content_files = \
	dconf-overview.xml		\
	dconf-service.xml		\
	dconf-editor.xml		\
	dconf-tool.xml

XSLTPROC_MAN_FLAGS = \
        --nonet \
        --stringparam man.output.quietly 1 \
        --stringparam funcsynopsis.style ansi \
        --stringparam man.th.extra1.suppress 1 \
        --stringparam man.authors.section.enabled 0 \
        --stringparam man.copyright.section.enabled 0

%.1: %.xml
	$(AM_V_GEN) $(XSLTPROC) $(XSLTPROC_MAN_FLAGS) http://docbook.sourceforge.net/release/xsl/current/manpages/docbook.xsl $<

dconf.1: dconf-tool.xml
	$(AM_V_GEN) $(XSLTPROC) $(XSLTPROC_MAN_FLAGS) http://docbook.sourceforge.net/release/xsl/current/manpages/docbook.xsl $<

dconf.7: dconf-overview.xml
	$(AM_V_GEN) $(XSLTPROC) $(XSLTPROC_MAN_FLAGS) http://docbook.sourceforge.net/release/xsl/current/manpages/docbook.xsl $<

man_MANS =

if ENABLE_MAN
man_MANS += \
        dconf-service.1 \
	dconf-editor.1 \
	dconf.1 \
	dconf.7
endif

EXTRA_DIST += dconf-service.xml dconf-editor.xml dconf-tool.xml dconf-overview.xml

DISTCLEANFILES = $(man_MANS)
