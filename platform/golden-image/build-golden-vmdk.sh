#!/usr/bin/env bash
# build-golden-vmdk.sh — convert a Rocky GenericCloud qcow2 into an ESXi-importable
# streamOptimized VMDK, verifying the source against a pinned sha256 and emitting a
# sha256 for the output.
#
# The output sha256 is the integrity anchor the ESXi-side fetch trusts: ESXi 8 has no
# CA trust store and its BusyBox wget segfaults on TLS, so the genesis flow fetches via
# python3 with cert verification OFF and verifies this hash instead (see
# platform/ovh-esxi/README.md "Layer 0").
#
# Provider-agnostic: runs in GitHub Actions, GitLab CI, or locally. Needs only
# qemu-img, curl, sha256sum.
#
# Usage:
#   build-golden-vmdk.sh <qcow2-url> <expected-qcow2-sha256> <out-basename>
# Produces <out-basename>.vmdk + <out-basename>.vmdk.sha256 in $WORKDIR (default: cwd).
set -euo pipefail

URL=${1:?qcow2 url required}
SRC_SHA=${2:?expected source sha256 required}
OUT=${3:?output basename required}
WORKDIR=${WORKDIR:-.}

cd "$WORKDIR"
qcow2=$(basename "$URL")

echo ">> downloading $qcow2"
curl -fSL --retry 3 -o "$qcow2" "$URL"

echo ">> verifying source sha256 (pinned)"
echo "$SRC_SHA  $qcow2" | sha256sum -c -

echo ">> converting qcow2 -> streamOptimized VMDK"
# streamOptimized = the compressed, sparse VMDK format ESXi imports (it is the OVA disk
# format). adapter_type lsilogic is the safe default; vmkfstools -i re-wraps it on the
# ESXi side, so the controller the VM actually uses (pvscsi) is independent of this.
qemu-img convert -p -f qcow2 -O vmdk \
  -o subformat=streamOptimized,adapter_type=lsilogic \
  "$qcow2" "$OUT.vmdk"

echo ">> emitting output sha256 (the ESXi-side integrity anchor)"
sha256sum "$OUT.vmdk" | tee "$OUT.vmdk.sha256"

echo ">> done:"
ls -lh "$OUT.vmdk" "$OUT.vmdk.sha256"
