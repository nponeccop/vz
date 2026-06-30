#!/usr/bin/env bash
# minify.sh — strace-driven image minification run INSIDE a buildah working
# container (the privileged-build-pod model from TASKS.md "C").
#
# The trace runs with the container's own rootfs as `/`, so the symlink closure
# (dir-links.js) and the loader/nss/hosts globs resolve against the *same* rootfs
# that was traced. This removes the historic "tracing a foreign rootfs is
# unsupported" limitation (host `/lib /lib64 /etc` were hardcoded): the working
# container IS the build host now. Fully rootless via `buildah unshare`.
#
# The build/trace dependencies installed into the working container (strace, and
# whatever --install pulls in) are left behind — only the spec'd closure is copied
# into a fresh scratch image. That is the "production images shouldn't ship build
# dependencies" split, realised by tracing instead of a hand-written multistage.
#
#   minify.sh --base <ref> --out <ref> --install '<sh>' --trace '<sh>' [--spec <file>]
#
#   --base    base image to install + trace in (e.g. a ubi-minimal / rocky base)
#   --out     localhost/<name>:<tag> for the minified image (imagePullPolicy:Never)
#   --install shell run in the container to install the app + its RUNTIME deps
#   --trace   shell run under strace to exercise the app; it MUST touch every code
#             path whose files you need (this step is inherently unsafe — a missed
#             path means a missing file at runtime)
#   --spec    optional: also write the computed file list here for inspection
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

# buildah mount needs a user namespace when ROOTLESS; re-exec ourselves into one.
# But when we're already real root (e.g. inside a privileged build pod) we must NOT:
# root has no /etc/subuid range, so `buildah unshare` re-execs itself forever
# ("buildah-in-a-user-namespace-in-a-user-namespace-in-a...") and dies. Real root
# can buildah from/run/mount directly, so only unshare for the rootless case.
if [ "$(id -u)" != 0 ] && [ -z "${_VZ_UNSHARE:-}" ]; then
  exec buildah unshare env _VZ_UNSHARE=1 "$0" "$@"
fi

BASE= OUT= INSTALL=true TRACE= SPECOUT=
while [ $# -gt 0 ]; do
  case $1 in
    --base)    BASE=$2; shift 2;;
    --out)     OUT=$2; shift 2;;
    --install) INSTALL=$2; shift 2;;
    --trace)   TRACE=$2; shift 2;;
    --spec)    SPECOUT=$2; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$BASE" ] && [ -n "$OUT" ] && [ -n "$TRACE" ] || {
  echo "usage: minify.sh --base <ref> --out <ref> --install '<sh>' --trace '<sh>' [--spec <file>]" >&2
  exit 2
}

ctr=$(buildah from "$BASE")
work=$(mktemp -d)
cleanup() {
  buildah umount "$ctr" >/dev/null 2>&1 || true
  buildah rm "$ctr"     >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

echo ">>> install trace tooling (left behind; not in the closure)"
buildah run "$ctr" -- sh -c \
  'command -v strace >/dev/null 2>&1 || microdnf install -y strace || dnf install -y strace || apk add --no-cache strace'

echo ">>> install the workload"
buildah run "$ctr" -- sh -c "$INSTALL"

echo ">>> trace the workload (only this run is traced — install temp is not)"
buildah run --cap-add CAP_SYS_PTRACE "$ctr" -- \
  strace -e trace=open,openat,execve -f -q -o /tmp/vz-strace.log sh -c "$TRACE" || true

mp=$(buildah mount "$ctr")

# Drop pseudo-filesystems and ldconfig caches (same filter the host scripts used).
grep_nosys() { grep -vE '^/(dev|sys|run|tmp|proc)/|^(/etc/ld.so.cache|/|/var/cache/ldconfig/aux-cache)$'; }

echo ">>> compute the closure (dir-links.js resolves symlinks against the container rootfs)"
spec="$work/spec"
{
  node "$HERE/dir-links.js" <(
    {
      # paths the app actually opened/exec'd, as seen inside the container ( / == $mp )
      grep -E '^[0-9]+ +[a-z]+\(' "$mp/tmp/vz-strace.log" | grep -Ev 'ENOENT' \
        | cut -d '"' -f2 | grep_nosys | sort -u
      # loader + nss + resolv + /etc/hosts that the trace can't observe but DNS needs,
      # found under the container rootfs and reported as container-absolute paths
      find -L "$mp/lib" "$mp/lib64" -maxdepth 1 \
        \( -name 'libnss_files.so*' -o -name 'libnss_dns.so*' -o -name 'ld-linux*.so*' \
           -o -name 'ld-musl-*.so*' -o -name 'libresolv.so*' \) 2>/dev/null \
        | sed "s|^${mp}||"
      [ -f "$mp/etc/hosts" ] && echo /etc/hosts
    } | grep_nosys
  ) "$mp" | grep_nosys
  # fixed must-have mount points / dirs / runtime files
  cat <<'EOF'
/run
/dev
/sys
/tmp
/proc
/etc/resolv.conf
/lib
/mnt
/sbin
/usr/sbin
/srv
/opt
/bin
EOF
} | sort -u > "$spec"

[ -n "$SPECOUT" ] && { cp "$spec" "$SPECOUT"; echo ">>> spec written to $SPECOUT ($(wc -l <"$spec") entries)"; }

echo ">>> copy only the closure into a fresh rootfs"
rootfs="$work/rootfs"
mkdir -p "$rootfs"
# -a preserves symlinks as symlinks; dir-links.js already added their targets too.
# --ignore-missing-args: some fixed entries (e.g. /etc/resolv.conf) don't exist in
# the base — the runtime injects them — so skip rather than fail.
rsync -a --ignore-missing-args --files-from="$spec" "$mp/" "$rootfs/"

# Guarantee the kernel/runtime mount points exist even if the base lacked them,
# so bind mounts (proc, resolv.conf, tmpfs) have targets in the minified image.
mkdir -p "$rootfs"/{run,dev,sys,tmp,proc,mnt,opt,srv,etc}
chmod 1777 "$rootfs/tmp"

echo ">>> wrap the minified rootfs into an OCI image"
"$HERE/oci.sh" base "$OUT" "$rootfs"

echo ">>> done: $OUT"
