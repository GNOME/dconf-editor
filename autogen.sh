#!/bin/sh

set -e

test -n "$srcdir" || srcdir=`dirname "$0"`
test -n "$srcdir" || srcdir=.

olddir=`pwd`
cd "$srcdir"

if automake-1.11 --version > /dev/null 2>&1; then
  automake_suffix='-1.11'
else
  automake_suffix=''
fi

AUTORECONF=`which autoreconf`
if test -z $AUTORECONF; then
    echo "*** No autoreconf found, please install it ***"
    exit 1
fi

CFLAGS=${CFLAGS=-ggdb}
LDFLAGS=${LDFLAGS=-Wl,-O1}
export CFLAGS LDFLAGS

autoreconf --force --install --verbose

cd "$olddir"

if test -z "$NOCONFIGURE"; then
  "$srcdir"/configure "$@"
fi
