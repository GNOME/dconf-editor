AM_CFLAGS = -I$(top_srcdir)/common $(glib_CFLAGS) $(dbus_CFLAGS) \
		-Wall -Wmissing-prototypes -Wwrite-strings -g

noinst_LIBRARIES = libdconf-writer.a

libdconf_writer_a_SOURCES = \
	dconf-writer-file.c	\
	dconf-writer.c		\
	dconf-writer-merge.c	\
	dconf-writer-unset.c    \
	dconf-writer-lock.c	\
	dconf-writer-config.c


noinst_HEADERS = \
	dconf-writer-private.h	\
	dconf-writer-config.h	\
	dconf-writer.h

libexec_PROGRAMS = dconf-writer
dconf_writer_LDADD = $(glib_LIBS) $(dbus_LIBS) libdconf-writer.a
dconf_writer_SOURCES = dconf-dbus-writer.c
