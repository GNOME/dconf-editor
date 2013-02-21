include $(top_srcdir)/Makefile.gtester

noinst_LIBRARIES = \
	libdconf-gdbus-thread.a			\
	libdconf-gdbus-thread-shared.a		\
	libdconf-gdbus-filter.a			\
	libdconf-gdbus-filter-shared.a

libdconf_gdbus_thread_a_CFLAGS = $(gio_CFLAGS) -DG_LOG_DOMAIN=\"dconf\"
libdconf_gdbus_thread_a_SOURCES = \
	dconf-gdbus-thread.c

libdconf_gdbus_thread_shared_a_CFLAGS = $(libdconf_gdbus_thread_a_CFLAGS) -fPIC -DPIC
libdconf_gdbus_thread_shared_a_SOURCES = $(libdconf_gdbus_thread_a_SOURCES)

libdconf_gdbus_filter_a_CFLAGS = $(gio_CFLAGS) -DG_LOG_DOMAIN=\"dconf\"
libdconf_gdbus_filter_a_SOURCES = \
	dconf-gdbus-filter.c

libdconf_gdbus_filter_shared_a_CFLAGS = $(libdconf_gdbus_filter_a_CFLAGS) -fPIC -DPIC
libdconf_gdbus_filter_shared_a_SOURCES = $(libdconf_gdbus_filter_a_SOURCES)
