dconf_etcdir = /etc/xdg/dconf
dconf_etc_DATA = \
	system.db	\
	default.db	\
	dconf.conf

system.db: empty-db
	cp empty-db system.db

default.db: empty-db
	cp empty-db default.db

dbusservicedir = /usr/share/dbus-1/services
dbusservice_DATA = \
	ca.desrt.dconf.writer.user.service

%.service: %.service.in
	sed -e "s|\@libexecdir\@|$(libexecdir)|" $< > $@

dbussystemservicedir = /usr/share/dbus-1/services
dbussystemservice_DATA = \
	ca.desrt.dconf.writer.default.service	\
	ca.desrt.dconf.writer.system.service

CLEANFILES = system.db default.db *.service
