#!/usr/bin/env bash
set -ex
DIR=$1
if [ -z "$DIR" ]
then
	echo >&2 DIR cannot be empty
	exit
fi
mkdir -p $1/rootfs
sudo rsync -al / $DIR/rootfs --files-from=$DIR.spec
