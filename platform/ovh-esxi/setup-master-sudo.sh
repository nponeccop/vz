#!/bin/sh
# setup-master-sudo.sh — give a user passwordless sudo via the wheel group.
# Run as root on the master (Alpine). Idempotent.
#
# Usage: setup-master-sudo.sh [USER]
#   USER defaults to $SUDO_USER (the invoking user when run via sudo), else the
#   current user.
set -e

TARGET_USER=${1:-${SUDO_USER:-$(id -un)}}

if ! command -v sudo >/dev/null 2>&1; then
    apk add --no-cache sudo
fi

id "$TARGET_USER" >/dev/null 2>&1 || { echo "ERROR: user '$TARGET_USER' not found" >&2; exit 1; }
adduser "$TARGET_USER" wheel 2>/dev/null || true

if ! grep -q '^%wheel ALL=(ALL) NOPASSWD: ALL' /etc/sudoers; then
    sed -i 's/^%wheel ALL=(ALL:ALL) ALL/# &/' /etc/sudoers
    sed -i 's/^%wheel ALL=(ALL) ALL/# &/' /etc/sudoers
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
fi

visudo -c -f /etc/sudoers
echo "Done: $TARGET_USER can now run sudo without a password."
