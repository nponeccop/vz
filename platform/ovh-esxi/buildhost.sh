#!/bin/sh
# buildhost.sh — provision a bootstrapped Rocky node into the vz build/control
# host (vz stack + k3s dev cluster). Run after ../../ansible/bootstrap.sh.
#
#   ./buildhost.sh <ip> [user]      user defaults to the operator (whoami)
[ -z "$1" ] && echo "usage: $0 <ip> [user]" >&2 && exit 1
ip=$1
user=${2:-$(whoami)}
export ANSIBLE_HOST_KEY_CHECKING=False
exec ansible-playbook -i "$ip", -u "$user" "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/buildhost.yaml"
