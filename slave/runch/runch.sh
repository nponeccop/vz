#!/usr/bin/env bash
set -ex
bundle=$1
uu=$(jshon -F $bundle/config.json -e root -e path -u -pp -e process -e args -au -pp -e user -e uid -u -p -e gid -u -pp -e cwd -u |
(
read root
read args
read uid
read gid
read cwd
cd $bundle$cwd 
echo $uid:$gid $bundle/$root $args
)
)

chroot --userspec $uu
