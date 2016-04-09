#!/usr/bin/env bash

set -ex -o pipefail
container_id=$1
pid=$(cat /run/opencontainer/chroots/$container_id/state.json | jshon -e init_process_pid -u)
pgid=$(ps -o pgid="" $pid | awk '{print $1}')
sudo kill -- -$pgid

echo waiting for $pid to exit
while [ -d /proc/$pid ] ; do sleep 1; done
echo process $pid exited
$(dirname $0)/runch delete $container_id
