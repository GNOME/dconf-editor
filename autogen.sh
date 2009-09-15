#!/bin/bash

set -e

if [ "$1" = "clean" ]; then
  rm -f aclocal.m4 configure missing install-sh \
        depcomp ltmain.sh config.guess config.sub \
        `find . -name Makefile.in` compile ltmain.sh
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

./configure --enable-maintainer-mode --enable-silent-rules "$@"
