#!/usr/bin/env bash

if [ -f "$1/config.json" ]
then
	sudo tar --numeric-owner -cJvf $(basename $1).txz -C $1 .
else
	echo >&2 Usage: foo {bundle-path}
fi
