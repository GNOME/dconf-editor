include $(top_srcdir)/Makefile.gtester

AM_CFLAGS = -Wall -Wmissing-prototypes -Wwrite-strings -DSRCDIR=\"$(abs_srcdir)\"
INCLUDES = -I$(top_srcdir)/common -I$(top_srcdir)/engine -I$(top_srcdir)/client $(gio_CFLAGS) -I$(top_srcdir)/dbus-1 $(dbus_CFLAGS) -I$(top_srcdir)/gvdb

noinst_LIBRARIES = libdconf-dbus-stub.a
noinst_PROGRAMS = $(TEST_PROGS) gsettings dbus1

gsettings_LDADD = $(gio_LIBS)
dbus1_LDADD = -L../dbus-1 -ldconf-dbus-1 $(glib_LIBS)

TEST_PROGS += paths
paths_LDADD = ../common/libdconf-common.a $(gio_LIBS)
paths_SOURCES = paths.c

TEST_PROGS += changeset
changeset_LDADD = ../common/libdconf-common.a $(glib_LIBS)
changeset_SOURCES = changeset.c

engine_LIBS = \
	../engine/libdconf-engine.a	\
	../shm/libdconf-shm.a		\
	../common/libdconf-common.a

engine_with_stub_LIBS = \
	$(engine_LIBS)			\
	libdconf-dbus-stub.a

client_LIBS = \
	../client/libdconf-client.a	\
	$(engine_LIBS)			\
	../gdbus/libdconf-gdbus.a

stub_client_LIBS = \
	../client/libdconf-client.a	\
	$(engine_with_stub_LIBS)

libdconf_dbus_stub_a_SOURCES = \
	dconf-dbus-stub.c

TEST_PROGS += gvdb
gvdb_LDADD = $(glib_LIBS)
gvdb_SOURCES = \
	../gvdb/gvdb-reader.c		\
	gvdb.c
EXTRA_DIST = \
	gvdbs/empty_gvdb		\
	gvdbs/example_gvdb		\
	gvdbs/example_gvdb.big-endian	\
	gvdbs/file_empty		\
	gvdbs/file_too_small		\
	gvdbs/invalid_header		\
	gvdbs/nested_gvdb

TEST_PROGS += gdbus-thread
gdbus_thread_CFLAGS = $(AM_CFLAGS) -DDBUS_BACKEND=\"/gdbus/thread\"
gdbus_thread_LDADD = $(gio_LIBS)
gdbus_thread_SOURCES = \
	../gdbus/dconf-gdbus-thread.c	\
	dbus.c

TEST_PROGS += gdbus-filter
gdbus_filter_CFLAGS = $(AM_CFLAGS) -DDBUS_BACKEND=\"/gdbus/filter\"
gdbus_filter_LDADD = $(gio_LIBS)
gdbus_filter_SOURCES = \
	../gdbus/dconf-gdbus-filter.c	\
	dbus.c

TEST_PROGS += engine
engine_LDADD = $(engine_with_stub_LIBS) $(glib_LIBS) -ldl
engine_SOURCES = engine.c

TEST_PROGS += client
client_LDADD = $(stub_client_LIBS) $(gio_LIBS)
client_SOURCES = client.c
EXTRA_DIST += \
	profile/broken-profile		\
	profile/colourful		\
	profile/dos			\
	profile/empty-profile		\
	profile/many-sources		\
	profile/no-newline-longline	\
	profile/test-profile		\
	profile/will-never-exist
