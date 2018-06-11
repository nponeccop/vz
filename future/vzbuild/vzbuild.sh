#!/usr/bin/env bash
function cmd_update
{
	set -ex
	local base=$1
	local root=$2
	./strace-parse.sh $1.trace >$1.parsed
	sudo ./strace-spec.sh $1.parsed $root >$1.spec
	sudo rm -r $1 || true
	./from-spec.sh $1 $root
	sudo rm -rf ../../oci_bundles/$1/rootfs
	mv $1/rootfs ../../oci_bundles/$1
	rmdir $1
	./from-bundle.sh ../../oci_bundles/$1
	local image=$1-*.txz
	if [ -f ../../vzbuild/images/$image ]
	then
		echo $image already exists
		rm $image
		return
	fi
	echo $image
	mv $image ../../vzmaster/images
}	

set -e -o pipefail
case $1 in
   update|foo)
      cmd_$1 $2 $3
      ;;
	*)
      echo "Invalid command: $1" >&2
	  exit
      ;;
esac
