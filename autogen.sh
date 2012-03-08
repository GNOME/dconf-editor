#!/bin/sh

set -e

test -n "$srcdir" || srcdir=`dirname "$0"`
test -n "$srcdir" || srcdir=.

olddir=`pwd`
cd "$srcdir"

if [ "$1" = "clean" ]; then
  rm -f aclocal.m4 configure config.* `find . -name Makefile.in` libtool
  rm -rf autom4te.cache m4 aux
  exit
fi

if automake-1.11 --version &> /dev/null; then
  automake_suffix='-1.11'
else
  automake_suffix=''
fi

mkdir -p m4 aux
gtkdocize --docdir docs --flavour no-tmpl
aclocal${automake_suffix} ${ACLOCAL_FLAGS}
autoheader
automake${automake_suffix} --add-missing --foreign
autoconf

CFLAGS=${CFLAGS=-ggdb}
LDFLAGS=${LDFLAGS=-Wl,-O1}
export CFLAGS LDFLAGS

cd "$olddir"

if test -z "$NOCONFIGURE"; then
  "$srcdir"/configure "$@"
fi

