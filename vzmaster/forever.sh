#!/bin/bash
# Restart the given command forever, 5s apart. stdout+stderr go to syslog (tag: forever).
set -x
while true
do
	$* || true
	sleep 5
done 2>&1 | logger -t forever
