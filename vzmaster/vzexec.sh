#!/usr/bin/env bash
function cmd_ps
{
	ps ax -o pgid,cmd | grep /home/$(whoami)/.vzexec | sed "s|/home/$(whoami)/.vzexec//bin/||g;s|/bin/bash ||;s|/home/$(whoami)/.vzexec/||;s|forever runch start bundles/||" | grep -vE "grep|sed" | sort -n -u
}

function cmd_mounts
{
	 grep -F /home/$(whoami) /proc/mounts | cut -f 2 -d ' ' | sed "s|/home/$(whoami)/.vzexec/bundles/\(.*\)/rootfs\(/.*\)\$|\1\t\2|" | column -t
}

function cmd_kill
{
	echo Not implemented
}


set -e -o pipefail
case $1 in
    ps|mounts)
      cmd_$1 $2
      ;;
	*)
      echo "Invalid command: $1" >&2
      echo "Available commands: ps mounts" >&2
	  exit
      ;;
esac
