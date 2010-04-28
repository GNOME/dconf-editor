#!/bin/bash

set -e

if [ "$1" = "clean" ]; then
  rm -f aclocal.m4 configure missing install-sh depcomp ltmain.sh \
        config.* `find . -name Makefile.in` compile libtool
  rm -rf autom4te.cache
  exit
fi

libtoolize --automake
aclocal
automake --add-missing --foreign
autoconf

CFLAGS=${CFLAGS=-ggdb -Werror}
LDFLAGS=${LDFLAGS=-Wl,-O1}
export CFLAGS LDFLAGS

./configure --enable-silent-rules "$@"
