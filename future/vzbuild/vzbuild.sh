#!/usr/bin/env bash
# vzbuild — strace-minifier front-end.
#
#   ./vzbuild.sh update <name> <root> [image-ref]
#
# Turns a captured strace into a minimal rootfs and wraps it straight into a
# loadable OCI base image via oci.sh (rootless buildah). This is the v3 path:
# the old oci_bundles/.txz tail (v2 runch bundles) is retired — `podman kube
# play` consumes OCI images, not bare tarballs. See ../../SPEC-v3.md
# ("Image distribution", "What v2 retires").
function cmd_update
{
	set -ex
	local base=$1
	local root=$2
	local ref=${3:-localhost/$base-base:v3}
	# strace -> file list -> minimal rootfs dir ($base/rootfs)
	./strace-parse.sh "$base.trace" >"$base.parsed"
	sudo ./strace-spec.sh "$base.parsed" "$root" >"$base.spec"
	sudo rm -rf "$base" || true
	./from-spec.sh "$base" "$root"
	# wrap the minified rootfs into a local OCI image for `podman image scp`
	./oci.sh base "$ref" "$base/rootfs"
}

set -e -o pipefail
case $1 in
   update)
      cmd_update "$2" "$3" "$4"
      ;;
	*)
      echo "Usage: $0 update <name> <root> [image-ref]" >&2
	  exit 1
      ;;
esac
