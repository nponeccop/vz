#!/usr/bin/env bash
set -ex

DIR=$(dirname $0)
OUT=$1
shift
strace -e 'trace=open,execve' -f -q -o strace.log $* || true

function grep_nosys {
	grep -vE '^/(dev|sys|run|tmp|proc)/|^(/etc/ld.so.cache|/|/var/cache/ldconfig/aux-cache)$';
}

(
node $DIR/dir-links.js <(

	cat strace.log | grep -E '^[0-9]+ +[a-z]+\(' | grep -Ev 'ENOENT' | cut -d '"' -f 2 | grep_nosys | sort -u
	echo /usr/lib/ld-linux.so.2
) | grep_nosys

cat <<bar
/run
/dev
/sys
/tmp
/proc
/etc/resolv.conf
/lib
bar
) | sort -u -o $OUT
