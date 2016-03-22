#!/bin/bash
set -x
while true
do
	$* || true
    sleep 5
done 2> >(logger -t forever) 1> >(logger -t forever -p info)


