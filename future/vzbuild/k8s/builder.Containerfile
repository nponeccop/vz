# builder.Containerfile — the vz-builder image the minify Job runs in.
#
# WHY THIS EXISTS: the off-the-shelf quay.io/buildah/stable image is built on
# Fedora, whose crun calls memfd_create(MFD_EXEC) — a flag that needs kernel
# >= 6.3. The lab build host is Rocky 9 (kernel 5.14), so nested buildah inside
# that image dies with "memfd_create(): Invalid argument".
#
# Building the builder FROM ubi9 pins crun/buildah to the el9 (5.14) toolchain,
# so the nested build works on the same kernel that built it. Everything the Job
# needs is baked in (buildah + skopeo for the wrap/export, nodejs for
# dir-links.js, rsync for the closure copy), so the per-run `dnf install` is gone.
#
# UBI packages are free/unauthenticated but a limited subset; if that bites, the
# drop-in alternative is a rocky-based UBI such as rockylinux/rockylinux:9-ubi
# (or :10-ubi — Rocky 10 — should Rocky 9 package staleness become limiting).
FROM registry.access.redhat.com/ubi9/ubi:latest

# install_weak_deps=0 keeps the builder lean; strace is NOT installed here — it is
# added to the *working* container by minify.sh so it lands outside the closure.
RUN dnf install -y --setopt=install_weak_deps=0 \
        buildah skopeo nodejs rsync \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# vfs is the reliable storage driver for buildah-in-a-pod (overlay-in-overlay is
# fiddly); the Job also sets STORAGE_DRIVER=vfs, this is the in-image default.
ENV STORAGE_DRIVER=vfs

CMD ["/bin/bash"]
