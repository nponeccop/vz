#!/usr/bin/env bash
# vzbuild oci — turn a minified rootfs into a loadable OCI image, layer the
# application source on top, and export an OCI archive for WAN push.
#
# This is the v3 wrap step the v2 pipeline lacked: v2 produced a bare rootfs
# tarball, which `podman kube play` cannot consume. See SPEC-v3.md ("Image
# distribution"). Images are built in two layers so a source edit ships only
# the small app layer:
#   base  — minified rootfs (runtime + libs); big, rare changes, pushed once
#   app   — application source; tiny, changes often
#
# Refs should be localhost/<name>:<tag> to match the push model
# (imagePullPolicy: Never). Uses rootless buildah/skopeo; no daemon, no registry.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  oci.sh base   <image-ref> <rootfs-dir>          wrap a minified rootfs into a single-layer base image
  oci.sh app    <image-ref> <base-ref> <app-dir>  layer app source onto a base image (second layer)
  oci.sh export <image-ref> <archive.tar>         export an OCI archive (oci-archive) for push

  e.g.
  oci.sh base   localhost/node-base:v3   ./rootfs
  oci.sh app    localhost/dns-resolver:v3 localhost/node-base:v3 ./src/dns-resolver
  oci.sh export localhost/dns-resolver:v3 out/dns-resolver.tar
EOF
  exit 2
}

cmd_base() {
  local ref=$1 rootfs=$2
  [ -d "$rootfs" ] || { echo "rootfs dir not found: $rootfs" >&2; exit 1; }
  local ctr
  ctr=$(buildah from scratch)
  # contents of <rootfs> become / ; rootless userns maps them to uid 0 inside
  buildah copy "$ctr" "$rootfs" / >/dev/null
  buildah config --created-by "vzbuild oci base" "$ctr"
  buildah commit --rm "$ctr" "$ref"
  echo "base   $ref   (from $rootfs)"
}

cmd_app() {
  local ref=$1 base=$2 app=$3
  [ -d "$app" ] || { echo "app dir not found: $app" >&2; exit 1; }
  local ctr
  ctr=$(buildah from "$base")
  buildah copy "$ctr" "$app" /app >/dev/null
  buildah config --workingdir /app --created-by "vzbuild oci app" "$ctr"
  buildah commit --rm "$ctr" "$ref"
  echo "app    $ref   (base $base + $app)"
}

cmd_export() {
  local ref=$1 archive=$2
  mkdir -p "$(dirname "$archive")"
  # No reference stored in the archive; the name is (re)assigned on load:
  #   skopeo copy oci-archive:<archive> containers-storage:<ref>
  skopeo copy "containers-storage:$ref" "oci-archive:$archive"
  echo "export $ref -> $archive"
}

case ${1:-} in
  base)   shift; [ $# -eq 2 ] || usage; cmd_base "$@";;
  app)    shift; [ $# -eq 3 ] || usage; cmd_app "$@";;
  export) shift; [ $# -eq 2 ] || usage; cmd_export "$@";;
  *) usage;;
esac
