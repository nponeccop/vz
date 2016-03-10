#!/usr/bin/env bash
function cmd_push
{
	local image=$1
	if [ -z "$image" ]
	then
		echo "push: image cannot be empty" >&2
		exit
	fi

	if [ -f images/$image.txz ]
	then
		true
	else
		echo "images/$image.txz doesn't exist" >&2
		exit
	fi
	ansible all -m copy -a "src=images/$image.txz dest=/home/$USER/.vzexec/images/"
}

set -e
case $1 in
    push)
      cmd_$1 $2
      ;;
	*)
      echo "Invalid command: $1" >&2
	  exit
      ;;
esac

