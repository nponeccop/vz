#!/usr/bin/env bash
# recipes/gearmand.sh — minify the gearmand job server via the build-Job flow.
#
# This is the first DAEMON recipe (TASKS.md "C"). A daemon is harder to minify
# than a one-shot command: its full file closure only appears once it has
# actually *served* a job, so a bare "start it" trace misses the dispatch path.
# The --trace below is therefore a start -> exercise -> stop wrapper:
#
#   start    background gearmand on 127.0.0.1:4730
#   exercise register a 'reverse' worker (runs /usr/bin/rev) and submit one job,
#            forcing the worker-registration + SUBMIT_JOB + dispatch + WORK_COMPLETE
#            paths and loading every .so / config file the running daemon touches
#   stop     kill the worker and the daemon so strace (-f follows the backgrounded
#            child) flushes and the closure is complete
#
# Base is ROCKY, not UBI: gearmand lives in EPEL and pulls runtime deps that need
# the CRB repo, neither of which the free UBI subset carries. The minifier strips
# the fat Rocky base down to the traced closure, so a heavy build base is free.
# (Move BASE to rockylinux/rockylinux:10-ubi if Rocky 9 packages get too stale.)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

BASE=${BASE:-quay.io/rockylinux/rockylinux:9}
OUT=${OUT:-localhost/gearmand-min:job}

# --- install: gearmand + its runtime deps (left behind; only the closure ships)
INSTALL='set -eux
dnf install -y "dnf-command(config-manager)" epel-release
dnf config-manager --set-enabled crb
dnf install -y gearmand
command -v gearmand
command -v gearman'

# --- trace: start -> exercise (one real job) -> stop --------------------------
# /bin/sh on Rocky is bash, so /dev/tcp readiness probing works. Each step is a
# child of the traced shell, so strace -f captures the daemon's served-job paths.
TRACE='set -eux
/usr/sbin/gearmand --listen=127.0.0.1 --port=4730 \
  --verbose=INFO --log-file=stderr --pid-file=/tmp/gearmand.pid &
GMD=$!
# wait for the listener to accept connections (up to ~5s)
for i in $(seq 1 50); do
  (exec 3<>/dev/tcp/127.0.0.1/4730) 2>/dev/null && { exec 3>&-; break; }
  sleep 0.1
done
# exercise a full round trip: a worker that reverses input, one submitted job
gearman -h 127.0.0.1 -p 4730 -w -c 1 -f reverse -- /usr/bin/rev &
WRK=$!
printf hello | gearman -h 127.0.0.1 -p 4730 -f reverse
# stop cleanly so the trace closes over only the runtime files
kill "$WRK" 2>/dev/null || true
kill "$GMD" 2>/dev/null || true
wait 2>/dev/null || true'

exec "$HERE/../run-minify-job.sh" "$BASE" "$OUT" "$INSTALL" "$TRACE"
