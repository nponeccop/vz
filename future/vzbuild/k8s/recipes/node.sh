#!/usr/bin/env bash
# recipes/node.sh — minify the node.js worker RUNTIME base via the build-Job flow.
#
# This produces the node-base layer (SPEC-v3.md "Two layers: base + app"): the
# node runtime + the shared libs / data files it loads, with NO application code.
# The worker's own source and node_modules ship in the small app layer on top, so
# this base only has to carry node's runtime closure.
#
# Unlike gearmand this is NOT a daemon: node runs the exercise script once and
# exits, so a plain one-shot --trace is enough (no start->exercise->stop wrapper).
# The script must touch every runtime path the worker needs, because an untraced
# path is a missing file at run time:
#
#   crypto/hash     OpenSSL init + RNG
#   net.connect     socket() + connect() (the gearman-client path the worker uses)
#   dns.lookup      getaddrinfo -> libnss_files / libnss_dns / libresolv
#   dns.resolve4    node's bundled c-ares -> reads /etc/resolv.conf
#   Intl + tls      forces ICU data + TLS secure-context init
#
# strace -f follows node's libuv threadpool threads, so the getaddrinfo opens that
# happen off the main thread are captured too. setTimeout keeps the event loop
# alive long enough for the async DNS work (and its lib loads) to complete.
#
# Base is ROCKY (full), not UBI: we enable the nodejs:20 AppStream module, which
# the free UBI subset does not carry. The minifier strips the fat base + npm +
# headers + the package manager down to the traced closure, so the base is free.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

BASE=${BASE:-quay.io/rockylinux/rockylinux:9}
OUT=${OUT:-localhost/node-min:job}

# --- install: a modern node runtime (left behind; only the closure ships) -----
INSTALL='set -eux
dnf module reset -y nodejs || true
dnf module enable -y nodejs:20 || dnf module enable -y nodejs:18 || true
dnf install -y nodejs
command -v node
node --version'

# --- trace: exercise the runtime paths the worker base must carry -------------
TRACE='node -e "
const dns=require(\"dns\"), net=require(\"net\"), tls=require(\"tls\"), crypto=require(\"crypto\");
crypto.randomBytes(16);
crypto.createHash(\"sha256\").update(\"x\").digest(\"hex\");
try { tls.createSecureContext(); } catch (e) {}
new Intl.NumberFormat(\"en-US\").format(1234.5);
const s = net.connect(4730, \"127.0.0.1\"); s.on(\"error\", () => {}); s.on(\"connect\", () => s.end());
dns.lookup(\"localhost\", () => {});
dns.resolve4(\"localhost\", () => {});
setTimeout(() => process.exit(0), 800);
"'

exec "$HERE/../run-minify-job.sh" "$BASE" "$OUT" "$INSTALL" "$TRACE"
