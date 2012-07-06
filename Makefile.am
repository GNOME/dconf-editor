include Makefile.gtester

ACLOCAL_AMFLAGS = -I m4 ${ACLOCAL_FLAGS}

SUBDIRS = gvdb common engine service gdbus gsettings dbus-1 tests client bin docs

if ENABLE_EDITOR
SUBDIRS += editor
endif

DISTCHECK_CONFIGURE_FLAGS = --enable-gtk-doc

.PHONY: lcov lcov-clean
# use recursive makes in order to ignore errors during check
lcov:
	-$(MAKE) $(AM_MAKEFLAGS) lcov-clean
	-$(MAKE) $(AM_MAKEFLAGS) -k check
	lcov --directory $(top_builddir) --capture --output-file dconf-lcov.info --test-name dconf --no-checksum --compat-libtool
	LANG=C genhtml --prefix $(top_builddir) --output-directory lcov-html --legend --show-details dconf-lcov.info
	@echo
	@echo "     file://$(abs_top_builddir)/lcov-html/index.html"
	@echo

clean-am: lcov-clean gcno-clean

gcno-clean:
	-find -name '*.gcno' -exec rm -f '{}' ';'

lcov-clean:
	-lcov --directory $(top_builddir) -z
	-find -name '*.gcda' -exec rm -f '{}' ';'
	rm -rf lcov-html dconf-lcov.info
