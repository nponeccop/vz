#!/usr/bin/env bash
# Fleet build recipe — produces every image referenced by pods/*.yaml.
#
# This is the single place that answers "how is each image built", so reading a
# pod manifest (what runs) plus this file (how it is built) is enough to change
# behaviour 6 months from now. See SPEC-v3.md ("Desired state lives in git").
#
# Each image is built in TWO layers (vzbuild oci) so a source edit ships only
# the small app layer over the WAN (SPEC-v3.md, "Two layers: base + app"):
#   base  — minified rootfs (runtime + libs); big, changes rarely, pushed once
#   app   — application source; tiny, changes often
#
# Output: OCI archives under ./out/, ready for `vz apply` to push and
# `skopeo copy oci-archive:... containers-storage:...` to load on the node.
set -euo pipefail
cd "$(dirname "$0")"

# Path to the vzbuild oci wrapper (installed with the vz tooling).
VZ_OCI=${VZ_OCI:-../../future/vzbuild/oci.sh}

# --- base layers (rebuild only when the runtime changes) -------------------
# Each base is a minified rootfs DIRECTORY produced by the strace minifier
# (see ../../future/vzbuild: strace-trace.sh -> strace-spec.sh -> from-spec.sh).
# Point these at the rootfs dirs you minified for gearmand and node.js:
GEARMAND_ROOTFS=${GEARMAND_ROOTFS:-rootfs/gearmand}
NODE_ROOTFS=${NODE_ROOTFS:-rootfs/node}

"$VZ_OCI" base localhost/gearmand-base:v3 "$GEARMAND_ROOTFS"
"$VZ_OCI" base localhost/node-base:v3     "$NODE_ROOTFS"

# --- app layers (rebuilt on every source change) ---------------------------
"$VZ_OCI" app localhost/gearmand:v3     localhost/gearmand-base:v3 ./src/gearmand
"$VZ_OCI" app localhost/dns-resolver:v3 localhost/node-base:v3     ./src/dns-resolver

# --- export OCI archives for push ------------------------------------------
"$VZ_OCI" export localhost/gearmand:v3     out/gearmand.tar
"$VZ_OCI" export localhost/dns-resolver:v3 out/dns-resolver.tar
