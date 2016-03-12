#!/bin/sh

[ -z $1 ] && echo "Usage: bootstrap 1.2.3.4 [-k]" >&2 && exit
ansible-playbook -i $1, bootstrap.yaml $2
