#!/bin/sh

set -e

test -n "$srcdir" || srcdir=`dirname "$0"`
test -n "$srcdir" || srcdir=.

olddir=`pwd`
cd "$srcdir"

if automake-1.11 --version &> /dev/null; then
  automake_suffix='-1.11'
else
  automake_suffix=''
fi

mkdir -p m4 aux
intltoolize --force
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
