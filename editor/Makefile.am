bin_PROGRAMS = dconf-editor

AM_CFLAGS = $(gtk_CFLAGS) -I$(top_srcdir)/common -I$(top_srcdir)/client
AM_VALAFLAGS = --pkg gtk+-2.0
dconf_editor_LDADD = ../client/libdconf.la $(gtk_LIBS)
dconf_editor_SOURCES = dconf-editor.vala dconf.vapi
