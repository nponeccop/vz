#!/usr/bin/env bash

chroot_add_mount() {
  sudo mount "$@" && CHROOT_ACTIVE_MOUNTS=("$2" "${CHROOT_ACTIVE_MOUNTS[@]}")
}

parse() {
	set +x
	local bundle=$1
	local default=$2
	shift
	shift
	jshon -QF $bundle/config.json $* || echo $default
}

function cmd_start 
{
	set -ex
	local bundle=$1
	if [ -z "$bundle" ]
	then
		echo "list: bundle cannot be empty" >&2
		exit
	fi

	if [ -f $bundle/config.json ]
	then
		true
	else
		echo "$bundle/config.json doesn't exist" >&2
		exit
	fi
	local jshon="jshon -F $bundle/config.json"
	local root=$($jshon -e root -e path -u)
	local args=$($jshon -e process -e args -a -u | xargs)
	local uid=$(parse $bundle 0 -e process -e user -e uid)
	local gid=$(parse $bundle 0 -e process -e user -e gid)
	local cwd=/ # temporary until cwd is supported by chroot
	#cd $bundle$cwd

	local pid=$$
	local id=$(basename $bundle)
	local path=/run/opencontainer/chroots/$id
	sudo install -o $UID -d $path
	cat >$path/state.json <<-END
	{ "config" : $(cat $bundle/config.json)
	, "init_process_pid" : $pid
	, "id" : "$id"
	, "created" : "$(date -Is)"
	, "bundlePath" : "$(readlink -m $bundle)"
	}
	END
	local newroot=$bundle/$root
	# TODO parse config.json to enable the mounts
	chroot_add_mount proc "$newroot/proc" -t proc -o nosuid,noexec,nodev || true
	chroot_add_mount sys "$newroot/sys" -t sysfs -o nosuid,noexec,nodev,ro || true
	chroot_add_mount udev "$newroot/dev" -t devtmpfs -o mode=0755,nosuid || true
	exec sudo /usr/sbin/chroot --userspec $uid:$gid $newroot $args
}

function cmd_delete
{
	local id=$1
	local path=/run/opencontainer/chroots/$id/state.json
	if [ -z "$id" ]
	then
		echo "runch delete: id cannot be empty" >&2
		exit
	fi
	if [ -f $path ]
	then
		true
	else
		echo "$id container doesn't exist" >&2
		exit
	fi

	local bundle=$(jshon -F $path -e bundlePath -u)
	local root=$(jshon -F $path -e config -e root -e path -u)
	sudo umount $bundle/$root/{proc,sys,dev} || true
	rm $path
	sudo rmdir $(dirname $path)
}

function cmd_kill
{
	local id=$1
	local path=/run/opencontainer/chroots/$id/state.json
	if [ -z "$id" ]
	then
		echo "runch kill: id cannot be empty" >&2
		exit
	fi
	if [ -f $path ]
	then
		true
	else
		echo "$id container doesn't exist (wrong id or already deleted)" >&2
		exit
	fi

	local pid=$(jshon -F $path -e init_process_pid)
	sudo /usr/bin/kill -s 0 $pid 2>/dev/null || (
		echo "runch kill: ($pid) no such process (container $id is destroyed)" >&2
		false
	) || exit

	sudo /usr/bin/kill $pid
	echo waiting for $pid to exit
	while [ -d /proc/$pid ] ; do sleep 1; done
	echo process $pid exited
	cmd_delete $id
}

set -e
case $1 in
    start|kill|delete)
      cmd_$1 $2
      ;;
	"")
		echo "Empty command" >&2
		;;
	*)
      echo "Invalid command: $1" >&2
	  exit
      ;;
esac
