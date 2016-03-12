#!/usr/bin/env bash
function cmd_start 
{
	set -e
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
	local uid=$($jshon -e process -e user -e uid)
	local gid=$($jshon -e process -e user -e gid)
	local cwd=/ # temporary until cwd is supported by chroot
	#cd $bundle$cwd
	sudo /usr/sbin/chroot --userspec $uid:$gid $bundle/$root $args
	local pid=$!
	local id=$(basename bundle)
	local path=/run/opencontainer/chroots/$id
	sudo install -o $UID -d $path
	cat >$path/state.json <<-END
	{ "config" : $(cat $bundle/config.json)
	, "init_process_pid" : $pid
	, "id" : "$id"
	, "created" : "$(date -Is)"
	}
	END
}

function cmd_kill
{
	local id=$1
	kill $(jshon </run/opencontainer/chroots/$id/state.json -e init_process_pid)
}

set -e
case $1 in
    start|kill)
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
