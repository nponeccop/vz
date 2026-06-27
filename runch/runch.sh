#!/usr/bin/env bash
# Minimal OCI-bundle runner: chroot into bundle/<root.path> running process.args,
# tracking state under /run/opencontainer/chroots/<id>. Parses the OCI config with jq.

chroot_add_mount() {
  sudo mount "$@" && CHROOT_ACTIVE_MOUNTS=("$2" "${CHROOT_ACTIVE_MOUNTS[@]}")
}

function cmd_start
{
	set -ex
	local bundle=$1
	[ -z "$bundle" ] && { echo "start: bundle cannot be empty" >&2; exit; }
	[ -f "$bundle/config.json" ] || { echo "$bundle/config.json doesn't exist" >&2; exit; }

	local cfg=$bundle/config.json
	local root args uid gid
	root=$(jq -r '.root.path' "$cfg")
	# NOTE: args are word-split below, so each element must be space-free
	# (wrap complex workloads in a script inside the rootfs).
	args=$(jq -r '.process.args[]' "$cfg" | xargs)
	uid=$(jq -r '.process.user.uid // 0' "$cfg")
	gid=$(jq -r '.process.user.gid // 0' "$cfg")

	local pid=$$
	local id; id=$(basename "$bundle")
	local path=/run/opencontainer/chroots/$id
	sudo install -o "$UID" -d "$path"
	cat >"$path/state.json" <<-END
	{ "config" : $(cat "$cfg")
	, "init_process_pid" : $pid
	, "id" : "$id"
	, "created" : "$(date -Is)"
	, "bundlePath" : "$(readlink -m "$bundle")"
	}
	END
	local newroot=$bundle/$root
	# TODO parse config.json mounts instead of hardcoding
	chroot_add_mount proc "$newroot/proc" -t proc -o nosuid,noexec,nodev || true
	chroot_add_mount sys "$newroot/sys" -t sysfs -o nosuid,noexec,nodev,ro || true
	chroot_add_mount udev "$newroot/dev" -t devtmpfs -o mode=0755,nosuid || true
	exec sudo /usr/sbin/chroot --userspec "$uid:$gid" "$newroot" $args
}

function cmd_delete
{
	local id=$1
	local path=/run/opencontainer/chroots/$id/state.json
	[ -z "$id" ] && { echo "runch delete: id cannot be empty" >&2; exit; }
	[ -f "$path" ] || { echo "$id container doesn't exist" >&2; exit; }

	local bundle root
	bundle=$(jq -r '.bundlePath' "$path")
	root=$(jq -r '.config.root.path' "$path")
	sudo umount "$bundle/$root"/{proc,sys,dev} || true
	rm "$path"
	sudo rmdir "$(dirname "$path")"
}

function cmd_kill
{
	local id=$1
	local path=/run/opencontainer/chroots/$id/state.json
	[ -z "$id" ] && { echo "runch kill: id cannot be empty" >&2; exit; }
	[ -f "$path" ] || { echo "$id container doesn't exist (wrong id or already deleted)" >&2; exit; }

	local pid; pid=$(jq -r '.init_process_pid' "$path")
	sudo /usr/bin/kill -s 0 "$pid" 2>/dev/null || {
		echo "runch kill: ($pid) no such process (container $id is destroyed)" >&2
		exit
	}
	sudo /usr/bin/kill "$pid"
	echo "waiting for $pid to exit"
	while [ -d /proc/$pid ]; do sleep 1; done
	echo "process $pid exited"
	cmd_delete "$id"
}

set -e
case $1 in
    start|kill|delete)
      cmd_$1 "$2"
      ;;
	"")
		echo "Empty command" >&2
		;;
	*)
      echo "Invalid command: $1" >&2
	  exit
      ;;
esac
