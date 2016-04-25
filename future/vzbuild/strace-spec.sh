#!/usr/bin/env bash
set -ex

DIR=$(dirname $0)
IN=$1

function grep_nosys {
	grep -vE '^/(dev|sys|run|tmp|proc)/|^(/etc/ld.so.cache|/|/var/cache/ldconfig/aux-cache)$';
}

(
node $DIR/dir-links.js <(
	cat $IN
	find -L /lib -maxdepth 1 -name 'libnss_files.so*' -or -name 'libnss_dns.so*' -or -name 'ld-linux.so*'
	find -L /etc -maxdepth 1 -name 'hosts'
) | grep_nosys

cat <<bar
/run
/dev
/sys
/tmp
/proc
/etc/resolv.conf
/lib
/mnt
/sbin
/usr/sbin
/srv
/opt
/bin
bar
) | sort -u
