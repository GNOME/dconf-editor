dconfetcdir = $(sysconfdir)/dconf
dconfetc_DATA = \
	system.db	\
	default.db	\
	dconf.conf

default.db system.db: empty-db
	cp $< $@

dbusservice_DATA = \
	ca.desrt.dconf.writer.user.service	\
	ca.desrt.dconf.Service.service

%.conf: %.conf.in
	sed -e "s|\@sysconfdir\@|$(sysconfdir)|" $< > $@

%.service: %.service.in
	sed -e "s|\@libexecdir\@|$(libexecdir)|" $< > $@

dbussystemservice_DATA = \
	ca.desrt.dconf.writer.default.service	\
	ca.desrt.dconf.writer.system.service

CLEANFILES = system.db default.db *.service

EXTRA_DIST = \
	ca.desrt.dconf.writer.default.service.in	\
	ca.desrt.dconf.writer.system.service.in		\
	ca.desrt.dconf.writer.user.service.in		\
	ca.desrt.dconf.Service.service.in		\
	dconf.conf					\
	empty-db
