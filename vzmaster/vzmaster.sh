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

function cmd_start
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
cat >tmp-start.yaml <<PLAY
---
- hosts: all
  vars:
    vzexec:
      path: /home/$USER/.vzexec/
      image: $image
  tasks:
  - file: state=directory path={{ vzexec.path }}/bundles/{{ vzexec.image }}
  - unarchive: copy=no src={{ vzexec.path }}/images/{{ vzexec.image }}.txz dest={{ vzexec.path }}/bundles/{{ vzexec.image }}
    become: yes
PLAY
	ansible-playbook tmp-start.yaml
}

set -ex
case $1 in
    push|start)
      cmd_$1 $2
      ;;
	*)
      echo "Invalid command: $1" >&2
	  exit
      ;;
esac
