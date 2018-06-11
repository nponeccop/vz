#!/usr/bin/env bash
set -ex
DIR=$1
ROOT=$2
if [ -z "$DIR" ]
then
	echo >&2 DIR cannot be empty
	exit -1
fi

if ! [ -d "$ROOT" ]
then
	echo >&2 ROOT must be a directory
	exit -2
fi


mkdir -p $1/rootfs
sudo rsync -al $ROOT $DIR/rootfs --files-from=$DIR.spec

