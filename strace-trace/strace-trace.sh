#!/usr/bin/env bash
	strace -e 'trace=open,execve' -f -q -o strace.log $*
	cat strace.log | grep -Ev '(ENOENT|^(\+\+\+|---)|(\+\+\+|---)$)' | cut -d '"' -f 2 |  grep -vE '^/(dev|sys|run|tmp)/|^/etc/ld.so.cache$' | sort | uniq >spec

