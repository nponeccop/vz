#!/usr/bin/env bash
set -e -o pipefail

DIR=$(dirname $0)
IN=$1
ROOT=$2

[ -d $2 ] || (echo "Argument $2 is not a dir" ; exit -1)

function grep_nosys {
	grep -vE '^/(dev|sys|run|tmp|proc)/|^(/etc/ld.so.cache|/|/var/cache/ldconfig/aux-cache)$';
}

(
node $DIR/dir-links.js <(
	(
	cat $IN
	find -L /lib -maxdepth 1 -name 'libnss_files.so*' -or -name 'libnss_dns.so*' -or -name 'ld-linux.so*' -or -name 'libresolv.so*'
	find -L /etc -maxdepth 1 -name 'hosts'
	) | grep_nosys
) $ROOT | grep_nosys

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
