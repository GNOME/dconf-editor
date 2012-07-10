include Makefile.gtester

ACLOCAL_AMFLAGS = -I m4 ${ACLOCAL_FLAGS}

SUBDIRS = shm gvdb common engine service gdbus gsettings dbus-1 client bin docs tests

if ENABLE_EDITOR
SUBDIRS += editor
endif

DISTCHECK_CONFIGURE_FLAGS = --enable-gtk-doc
EXTRA_DIST = trim-lcov.py

.PHONY: lcov lcov-clean
# use recursive makes in order to ignore errors during check
lcov: lcov-clean
	-$(MAKE) $(AM_MAKEFLAGS) -k check
	lcov --directory $(top_builddir) --capture --test-name dconf | $(top_srcdir)/trim-lcov.py > dconf-lcov.info
	LANG=C genhtml --prefix $(top_builddir) --output-directory lcov-html --legend --show-details dconf-lcov.info
	@echo
	@echo "     file://$(abs_top_builddir)/lcov-html/index.html"
	@echo

clean-am: lcov-clean gcno-clean

gcno-clean:
	-find -name '*.gcno' -delete

lcov-clean:
	-lcov --directory $(top_builddir) -z
	find -name '*.gcda' -delete
	rm -rf lcov-html dconf-lcov.info
