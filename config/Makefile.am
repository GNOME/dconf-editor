dconfetcdir = $(sysconfdir)/dconf
dconfetc_DATA = \
	system.db	\
	default.db	\
	dconf.conf

system.db: empty-db
	cp empty-db system.db

default.db: empty-db
	cp empty-db default.db

dbusservice_DATA = \
	ca.desrt.dconf.writer.user.service

%.conf: %.conf.in
	sed -e "s|\@sysconfdir\@|$(sysconfdir)|" $< > $@

%.service: %.service.in
	sed -e "s|\@libexecdir\@|$(libexecdir)|" $< > $@

dbussystemservice_DATA = \
	ca.desrt.dconf.writer.default.service	\
	ca.desrt.dconf.writer.system.service

CLEANFILES = system.db default.db *.service
