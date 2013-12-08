include $(top_srcdir)/Makefile.gtester

noinst_LIBRARIES = libdconf-mock.a
noinst_PROGRAMS = $(TEST_PROGS)
noinst_HEADERS = dconf-mock.h

libdconf_mock_a_CFLAGS = $(glib_CFLAGS)
libdconf_mock_a_SOURCES = \
	dconf-mock-dbus.c	\
	dconf-mock-gvdb.c	\
	dconf-mock-shm.c

TEST_PROGS += paths
paths_CFLAGS = $(glib_CFLAGS)
paths_LDADD = \
	../common/libdconf-common.a	\
	$(gio_LIBS)
paths_SOURCES = paths.c

TEST_PROGS += changeset
changeset_CFLAGS = $(glib_CFLAGS)
changeset_LDADD = \
	../common/libdconf-common.a	\
	$(glib_LIBS)
changeset_SOURCES = changeset.c

TEST_PROGS += shm
shm_CFLAGS = $(glib_CFLAGS)
shm_LDADD = \
	../shm/libdconf-shm.a			\
	$(glib_LIBS)				\
	$(LIBDL)
shm_SOURCES = \
	shm.c					\
	tmpdir.h				\
	tmpdir.c

TEST_PROGS += gvdb
gvdb_CFLAGS = $(glib_CFLAGS) -DSRCDIR=\"$(abs_srcdir)\"
gvdb_LDADD = \
	../gvdb/libgvdb.a			\
	$(glib_LIBS)
gvdb_SOURCES = gvdb.c
EXTRA_DIST = \
	gvdbs/empty_gvdb			\
	gvdbs/example_gvdb			\
	gvdbs/example_gvdb.big-endian		\
	gvdbs/file_empty			\
	gvdbs/file_too_small			\
	gvdbs/invalid_header			\
	gvdbs/nested_gvdb

TEST_PROGS += gdbus-thread
gdbus_thread_CFLAGS = $(gio_CFLAGS) -DDBUS_BACKEND=\"/gdbus/thread\"
gdbus_thread_LDADD = \
	../gdbus/libdconf-gdbus-thread.a	\
	$(gio_LIBS)
gdbus_thread_SOURCES = dbus.c

TEST_PROGS += gdbus-filter
gdbus_filter_CFLAGS = $(gio_CFLAGS) -DDBUS_BACKEND=\"/gdbus/filter\"
gdbus_filter_LDADD = \
	../gdbus/libdconf-gdbus-filter.a	\
	$(gio_LIBS)
gdbus_filter_SOURCES = dbus.c

TEST_PROGS += libdbus-1
libdbus_1_CFLAGS = $(gio_CFLAGS) -DDBUS_BACKEND=\"/libdbus-1\"
libdbus_1_LDADD = \
	../dbus-1/libdconf-libdbus-1.a		\
	$(glib_LIBS)				\
	$(dbus_LIBS)
libdbus_1_SOURCES = dbus.c

TEST_PROGS += engine
engine_CFLAGS = $(glib_CFLAGS) -DSRCDIR=\"$(abs_srcdir)\"
engine_LDADD = \
	../engine/libdconf-engine.a		\
	../common/libdconf-common.a		\
	libdconf-mock.a				\
	$(glib_LIBS)				\
	$(LIBDL)				\
	-lm
engine_SOURCES = engine.c
EXTRA_DIST += \
	profile/broken-profile			\
	profile/colourful			\
	profile/dos				\
	profile/empty-profile			\
	profile/gdm				\
	profile/many-sources			\
	profile/no-newline-longline		\
	profile/test-profile			\
	profile/will-never-exist

TEST_PROGS += client
client_CFLAGS = $(gio_CFLAGS) -DSRCDIR=\"$(abs_srcdir)\"
client_LDADD = \
	../client/libdconf-client.a		\
	../engine/libdconf-engine.a		\
	../common/libdconf-common.a		\
	libdconf-mock.a				\
	$(gio_LIBS)
client_SOURCES = client.c
