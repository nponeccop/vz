#!/usr/bin/env bash
# run-build-job.sh — drive build-job.yaml (the traditional multistage build) on k3s.
#
#   run-build-job.sh <out-ref> <containerfile>
#
#   e.g. run-build-job.sh localhost/gearmand-trad:job recipes/gearmand.Containerfile
#
# The non-minified counterpart to run-minify-job.sh: bundles a single Containerfile
# into a ConfigMap, applies the build Job, waits, streams logs, then imports the
# exported oci-archive into the host podman store. The import half is identical to
# run-minify-job.sh, so a built image is interchangeable with a minified one for
# `vz apply` (dev or prod) — that's the "two scenarios, one workload" parity.
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 <out-ref> <containerfile>" >&2; exit 2; }
OUT=$1 CFILE=$2
[ -f "$CFILE" ] || { echo "Containerfile not found: $CFILE" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
OUTDIR=/var/tmp/vz-build-out

echo ">>> (re)create the Containerfile ConfigMap"
kubectl create configmap vz-build-file \
  --from-file=Containerfile="$CFILE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">>> (re)create the recipe ConfigMap"
kubectl create configmap vz-build-recipe \
  --from-literal=OUT="$OUT" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">>> (re)apply the Job"
kubectl delete job vz-build --ignore-not-found
kubectl apply -f "$HERE/build-job.yaml"

echo ">>> wait for completion"
kubectl wait --for=condition=complete --timeout=900s job/vz-build \
  || { kubectl logs job/vz-build || true; echo "JOB FAILED" >&2; exit 1; }
kubectl logs job/vz-build

echo ">>> import the exported image into the host podman store"
[ -f "$OUTDIR/image.tar" ] || { echo "no $OUTDIR/image.tar produced" >&2; exit 1; }
skopeo copy "oci-archive:$OUTDIR/image.tar" "containers-storage:$OUT"
echo ">>> imported $OUT into podman; run 'deploy-k3s'/'vz apply' to ship it"
