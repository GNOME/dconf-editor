include $(top_srcdir)/Makefile.gtester

noinst_LIBRARIES = libgvdb.a libgvdb-shared.a

libgvdb_a_CFLAGS = $(glib_CFLAGS) -DG_LOG_DOMAIN=\"gvdb\ \(via\ dconf\)\"
libgvdb_a_SOURCES = \
	gvdb-format.h	\
	gvdb-builder.h	\
	gvdb-builder.c	\
	gvdb-reader.h	\
	gvdb-reader.c

libgvdb_shared_a_CFLAGS = $(libgvdb_a_CFLAGS) -fPIC -DPIC
libgvdb_shared_a_SOURCES = $(libgvdb_a_SOURCES)
