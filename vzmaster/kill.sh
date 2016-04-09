#!/usr/bin/env bash

set -ex -o pipefail
pgid=$(ps -o pgid= $(cat /run/opencontainer/chroots/$1/state.json | jshon -e init_process_pid -u) | awk '{print $1}')

sudo kill -- -$pgid
