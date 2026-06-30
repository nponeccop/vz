# node.Containerfile — TRADITIONAL minimal-runtime build of the node.js worker base
# (the non-minified counterpart to recipes/node.sh).
#
# Same --installroot-onto-scratch technique as gearmand.Containerfile, producing the
# node-base layer (SPEC-v3.md "base + app"): the node runtime + its declared RPM
# closure, NO application code (the worker source + node_modules ship in the app
# layer on top, via oci.sh app).
#
# Builder is Rocky (full) so we can enable the nodejs:20 AppStream module, which the
# free UBI subset does not carry. For an off-the-shelf comparison point see
# registry.access.redhat.com/ubi9/nodejs-22-minimal — that is Red Hat's own
# traditional minimal node runtime image; this is the vz-built equivalent.
FROM quay.io/rockylinux/rockylinux:9 AS build
ARG ROOT=/mnt/rootfs
# Module state is per-root: enabling nodejs:20 in the builder's root does NOT carry
# into --installroot, which keeps its own /etc/dnf/modules.d and would otherwise pull
# the EL9 default stream (nodejs:16). Enable the stream IN the installroot so the
# traditional image matches recipes/node.sh (nodejs:20), not just whatever is default.
RUN mkdir -p "$ROOT" \
 && dnf -y --installroot="$ROOT" --releasever=9 module reset nodejs \
 && { dnf -y --installroot="$ROOT" --releasever=9 module enable nodejs:20 \
      || dnf -y --installroot="$ROOT" --releasever=9 module enable nodejs:18 ; } \
 && dnf install -y --installroot="$ROOT" --releasever=9 \
      --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
      --setopt=keepcache=0 nodejs \
 && dnf clean all --installroot="$ROOT" \
 && rm -rf "$ROOT"/var/cache/* "$ROOT"/var/log/* \
 && chroot "$ROOT" ldconfig \
 && chroot "$ROOT" /usr/bin/node --version

FROM scratch
COPY --from=build /mnt/rootfs /
# Base only: the worker app + node_modules are layered on top (oci.sh app).
ENTRYPOINT ["/usr/bin/node"]
