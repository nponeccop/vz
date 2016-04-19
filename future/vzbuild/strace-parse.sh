#!/usr/bin/env bash
set -ex
cat $1 | grep -Ev '^[+\-]|= -1 E[A-Z]+ \([A-Z][A-Za-z ]+\)$' | sed -e 's|^open("\(.*\)", O_.* = [0-9]*$|\1|;s|^execve("\(.*\)", \[.*]) = [0-9]*|\1|' | sort -u
