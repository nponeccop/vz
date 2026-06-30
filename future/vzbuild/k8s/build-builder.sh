#!/usr/bin/env bash
# build-builder.sh — build the vz-builder image and import it into k3s containerd.
#
#   build-builder.sh [<out-ref>]   (default localhost/vz-builder:v1)
#
# Builds builder.Containerfile with the host's (el9, kernel-5.14) buildah, then
# imports it into the k3s `k8s.io` containerd namespace so the minify Job can run
# it with imagePullPolicy:Never — registry-less, same as the workload images.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-localhost/vz-builder:v1}

echo ">>> build $OUT"
buildah bud -t "$OUT" -f "$HERE/builder.Containerfile" "$HERE"

echo ">>> import $OUT into k3s containerd (k8s.io)"
podman save "$OUT" | sudo k3s ctr -n k8s.io images import -

echo ">>> done: $OUT (imagePullPolicy:Never ready)"
