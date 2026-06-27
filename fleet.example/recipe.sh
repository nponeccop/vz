#!/usr/bin/env bash
# Fleet build recipe — produces every image referenced by nodes/*.yaml.
#
# This is the single place that answers "how is each image built", so reading a
# node manifest (what runs) plus this file (how it is built) is enough to change
# behaviour 6 months from now. See SPEC-v3.md ("Desired state lives in git").
#
# Each image is built in TWO layers so a source edit ships only the small app
# layer over the WAN (SPEC-v3.md, "Two layers: base + app"):
#   base  — runtime + libraries; big, changes rarely, pushed once
#   app   — application source; tiny, changes often
#
# Output: OCI archives under ./out/, ready for `vz apply` to push and
# `skopeo copy oci-archive:... containers-storage:...` to load on the node.
set -euo pipefail

cd "$(dirname "$0")"
OUT=out
mkdir -p "$OUT"

# build_app <image-tag> <base-image> <app-src-dir>
# Layers <app-src-dir> on top of <base-image> and exports an OCI archive.
build_app() {
  local tag=$1 base=$2 src=$3
  local ctr mnt
  ctr=$(buildah from "$base")
  buildah copy "$ctr" "$src" /app
  buildah config --workingdir /app "$ctr"
  buildah commit --rm "$ctr" "$tag"
  skopeo copy "containers-storage:$tag" "oci-archive:$OUT/${tag##*/}.tar:$tag"
  echo "built $tag -> $OUT/${tag##*/}.tar"
}

# --- base layers (rebuild only when the runtime changes) -------------------
# TODO(step 2): produce these via vzbuild OCI-wrap (strace-minified rootfs ->
# `buildah from scratch` + COPY). Until step 2 lands, point at a stock minimal
# image so the rest of the pipeline is exercisable end to end.
GEARMAND_BASE=${GEARMAND_BASE:-localhost/gearmand-base:v3}
NODE_BASE=${NODE_BASE:-localhost/node-base:v3}

# --- app layers (rebuilt on every source change) ---------------------------
build_app localhost/gearmand:v3     "$GEARMAND_BASE" ./src/gearmand
build_app localhost/dns-resolver:v3 "$NODE_BASE"     ./src/dns-resolver
