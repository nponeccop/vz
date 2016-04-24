#!/usr/bin/env bash

if [ -f "$1/config.json" ]
then
	txz=$(basename $1).txz
	sudo tar --numeric-owner -cJvf $txz -C $1 .
	mv $txz $(basename $1)-$(sha256sum $txz | cut -c 1-4).txz
else
	echo >&2 Usage: foo {bundle-path}
fi
