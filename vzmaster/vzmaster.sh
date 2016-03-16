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
cat >tmp-start.yaml <<PLAY
---
- hosts: all
  vars:
    vzexec:
      path: /home/$USER/.vzexec/
      image: $image
  tasks:
  - file: state=directory path={{ vzexec.path }}bundles/{{ vzexec.image }}
  - unarchive: copy=no src={{ vzexec.path }}images/{{ vzexec.image }}.txz dest={{ vzexec.path }}bundles/{{ vzexec.image }}
    become: yes
  - package: state=present name=jshon
  - file: state=directory path={{ vzexec.path }}bin
  - copy: src=../runch/runch.sh dest={{ vzexec.path }}bin/runch mode=755
  - command: "{{ vzexec.path }}/bin/runch start {{ vzexec.path }}bundles/{{ vzexec.image }}"
PLAY
	ansible-playbook tmp-start.yaml
}

function cmd_kill
{
	local container_id=$1
	echo '{ "vzexec" : {} }' | jshon -e vzexec -s "/home/$USER/.vzexec" -i path -s "$container_id" -i container_id -p >tmp-kill.json
	ansible-playbook -e @tmp-kill.json vzmaster-kill.yaml
}

set -ex
case $1 in
    push|start|kill)
      cmd_$1 $2
      ;;
	*)
      echo "Invalid command: $1" >&2
	  exit
      ;;
esac
