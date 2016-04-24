#!/usr/bin/env bash
function cmd_ps
{
	ps ax -o pgid,cmd | grep /home/$(whoami)/.vzexec | sed "s|/home/$(whoami)/.vzexec//bin/||g;s|/bin/bash ||;s|/home/$(whoami)/.vzexec/||;s|forever runch start bundles/||" | grep -vE "grep|sed" | sort -n -u
}

function cmd_start
{
	local image=$1
	if [ -z "$image" ]
	then
		echo "start: image cannot be empty" >&2
		exit -2
	fi

	if [ -f images/$image.txz ]
	then
		true
	else
		echo "start: images/$image.txz doesn't exist" >&2
		exit -1
	fi
	echo '{ "vzexec" : {} }' | jshon -e vzexec -s "/home/$USER/.vzexec/" -i path -s "$image" -i image -p >tmp-start.json
	ansible-playbook -e @tmp-start.json vzmaster-start.yaml
}

function cmd_kill
{
	echo Not implemented
}


set -e -o pipefail
case $1 in
    ps|kill)
      cmd_$1 $2
      ;;
	*)
      echo "Invalid command: $1" >&2
	  exit
      ;;
esac
