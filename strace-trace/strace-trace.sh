#!/usr/bin/env bash
set -ex
OUT=$1
shift
strace -e 'trace=open,execve' -f -q -o strace.log $*

node ./dir-links.js <(

(cat strace.log | grep -Ev '(ENOENT|^(\+\+\+|---)|(\+\+\+|---)$)' | cut -d '"' -f 2 |  grep -vE '^/(dev|sys|run|tmp|proc)/|^(/etc/ld.so.cache|/)$' ;
cat <<bar
/run
/dev
/sys
/tmp
/proc
/etc/resolv.conf
/lib
/usr/lib/ld-linux.so.2
bar

) | sort -u
) | sort -u -o $OUT
