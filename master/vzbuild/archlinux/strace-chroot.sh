#!/usr/bin/env bash
set -ex
DIR=$1
shift
../strace-trace.sh $DIR.spec $*
mkdir $DIR
sudo rsync -l / $DIR --files-from=$DIR.spec
sudo arch-chroot $DIR $*
