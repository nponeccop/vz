# gearmand.Containerfile — TRADITIONAL minimal-runtime build of the gearmand job
# server (the non-minified counterpart to recipes/gearmand.sh).
#
# Technique: install gearmand and its full RPM dependency closure into a fresh root
# with `dnf --installroot`, then COPY that root onto `FROM scratch`. This is exactly
# how ubi-micro itself is produced, so the result is a "from-scratch micro" image
# carrying only the declared closure of gearmand — no dnf, no docs, no weak deps.
#
# Builder is Rocky (full): gearmand lives in EPEL and pulls deps from CRB, neither
# of which the free UBI subset carries. The builder stage is discarded; only the
# installroot ships. Compare its size against recipes/gearmand.sh (strace-minified):
# this ships every RPM-declared file (safe), the minifier ships only what was opened
# (smaller, but a missed trace path = a missing file at run time).
#
# mariadb-connector-c (libmariadb.so.3) is gearmand's optional MySQL-queue backend,
# pulled only via Recommends; install_weak_deps=0 drops it, so the binary won't even
# print --version without it. We name it explicitly. Note where this surfaced: the
# chrooted `gearmand --version` smoke test below failed the BUILD — the traditional
# flow catches a missing runtime lib at build time, whereas a missed strace path in
# the minify flow only shows up when the container runs in production. The test must
# chroot into the installroot: run direct, it would use the host loader + ld.so.cache
# and never find libmariadb.so.3 (which lands in /usr/lib64/mariadb/).
FROM quay.io/rockylinux/rockylinux:9 AS build
ARG ROOT=/mnt/rootfs
RUN dnf install -y "dnf-command(config-manager)" epel-release \
 && dnf config-manager --set-enabled crb \
 && mkdir -p "$ROOT" \
 && dnf install -y --installroot="$ROOT" --releasever=9 \
      --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
      --setopt=keepcache=0 gearmand mariadb-connector-c \
 && dnf clean all --installroot="$ROOT" \
 && rm -rf "$ROOT"/var/cache/* "$ROOT"/var/log/* \
 && chroot "$ROOT" ldconfig \
 && chroot "$ROOT" /usr/sbin/gearmand --version

FROM scratch
COPY --from=build /mnt/rootfs /
# gearmand is a network daemon; bind /etc/resolv.conf etc. are injected at run time.
EXPOSE 4730
ENTRYPOINT ["/usr/sbin/gearmand"]
CMD ["--listen=0.0.0.0", "--port=4730", "--log-file=stderr", "--verbose=INFO"]
