#!/usr/bin/env bash
set -ex
DIR=$1
mkdir -p $1/rootfs
sudo rsync -al / $DIR/rootfs --files-from=$DIR.spec
