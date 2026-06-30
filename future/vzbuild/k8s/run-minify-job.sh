#!/usr/bin/env bash
# run-minify-job.sh — drive minify-job.yaml on the local k3s.
#
#   run-minify-job.sh <base-ref> <out-ref> <install-sh> <trace-sh>
#
#   e.g. run-minify-job.sh registry.access.redhat.com/ubi9/ubi-minimal:latest \
#          localhost/bash-min:test 'true' 'bash -c "echo hi"'
#
# Bundles the vzbuild scripts + the recipe into ConfigMaps, applies the Job, waits,
# streams the logs, then imports the exported oci-archive into the host podman store
# (and, if present, k3s containerd) so it's ready for `vz apply` (dev or prod).
set -euo pipefail
[ $# -eq 4 ] || { echo "usage: $0 <base-ref> <out-ref> <install-sh> <trace-sh>" >&2; exit 2; }
BASE=$1 OUT=$2 INSTALL=$3 TRACE=$4

HERE=$(cd "$(dirname "$0")" && pwd)
VZB=$(cd "$HERE/.." && pwd)
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
OUTDIR=/var/tmp/vz-build-out

echo ">>> (re)create the scripts ConfigMap"
kubectl create configmap vz-minify-scripts \
  --from-file="$VZB/minify.sh" \
  --from-file="$VZB/dir-links.js" \
  --from-file="$VZB/shebang.js" \
  --from-file="$VZB/oci.sh" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">>> (re)create the recipe ConfigMap"
kubectl create configmap vz-minify-recipe \
  --from-literal=BASE="$BASE" \
  --from-literal=OUT="$OUT" \
  --from-literal=INSTALL="$INSTALL" \
  --from-literal=TRACE="$TRACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">>> (re)apply the Job"
kubectl delete job vz-minify --ignore-not-found
kubectl apply -f "$HERE/minify-job.yaml"

echo ">>> wait for completion"
kubectl wait --for=condition=complete --timeout=900s job/vz-minify \
  || { kubectl logs job/vz-minify || true; echo "JOB FAILED" >&2; exit 1; }
kubectl logs job/vz-minify

echo ">>> import the exported image into the host podman store"
[ -f "$OUTDIR/image.tar" ] || { echo "no $OUTDIR/image.tar produced" >&2; exit 1; }
skopeo copy "oci-archive:$OUTDIR/image.tar" "containers-storage:$OUT"
echo ">>> imported $OUT into podman; run 'deploy-k3s'/'vz apply' to ship it"
