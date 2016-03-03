#!/usr/bin/env bash
set -ex
OUT=$1
shift
FOO=$*
strace -e 'trace=open,execve' -f -q -o strace.log $*
(cat strace.log | grep -Ev '(ENOENT|^(\+\+\+|---)|(\+\+\+|---)$)' | cut -d '"' -f 2 |  grep -vE '^/(dev|sys|run|tmp|proc)/|^/etc/ld.so.cache$' ; 

cat <<bar
/bin
/run
/dev
/sys
/tmp
/home
/root
/proc
/etc/resolv.conf
/lib
/sbin
/usr
/usr/sbin
/usr/lib/ld-linux.so.2
bar

) | sort | uniq >spec.new
join -v1 <(xargs -a spec.new readlink -m | sort) spec.new >>spec.new
sort spec.new | uniq > spec
rm spec.new
cat >$OUT <<Endofmessage
# Trace for $FOO
rsync -avzlK / \$1 --files-from <(cat <<FOO
$(cat spec)
FOO
)
Endofmessage
