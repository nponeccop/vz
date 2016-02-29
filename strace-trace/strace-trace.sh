#!/usr/bin/env bash
	strace -e 'trace=open' -o strace.log $*
	cat strace.log | grep -Ev '(ENOENT|^(\+\+\+|---))' | cut -d '"' -f 2 |  grep -vE '^/(dev)/|^/etc/ldd.cache$' | sort | uniq >spec

