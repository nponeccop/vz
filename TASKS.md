# vz v3 — remaining tasks

The v3 build order is **functionally complete** (see [`SPEC-v3.md`](SPEC-v3.md)):
desired state in git, `vzbuild oci` image wrap, `vz apply`, `vz ps`/`vz diff`,
and Quadlet boot units are all implemented in `vztool/` + `future/vzbuild/oci.sh`
and verified end-to-end on a Rocky 9 node (build → push → run → reboot-survives).

What is left is hardening and the real migration. Roughly in priority order.

## 1. Migrate the real workload (the actual proof)

The production shape is **gearmand + a node.js worker in one pod, talking over
`localhost`** (`hostNetwork: true`), under rootless Podman.

**Proven (demo) — the model carries the workload:**

- [x] node.js runtime through the whole vz pipeline: assembled a node rootfs
      (binary + `ldd` libs), `oci.sh base/app`, `vz apply`, served HTTP on the
      host's port via `hostNetwork`.
- [x] Two-container pod (gearmand + node.js worker using the **abraxas** gearman
      lib) deployed via `vz apply`; the worker reached gearmand on `127.0.0.1`
      (gearmand logged the loopback connection; worker logged an ECHO round-trip).
- [x] Full job round-trip: `vzreverse` job processed in-pod, **and** submitted
      from an external client on the build host over the network
      (scheduler → gearmand → in-pod worker → result). This is the real arch.

**Proven (cont.):**

- [x] **gearmand minified the vz way (153MB → 21MB)** and verified in the pod
      (worker connects over localhost, master job round-trips). Done via the
      *supported same-system flow*: install gearmand on the Rocky build host →
      strace it against the host's own `/` → `strace-spec.sh <parsed> /` →
      rsync `from-spec` → `oci.sh base`. The whole anti-fraud pod is now vz-built.

  Gotchas worth remembering:
  - The vzbuild minifier is **same-system only** — install + trace + build on
    one host with `ROOT=/`. Tracing an *isolated/foreign rootfs* (e.g. a pulled
    Debian image via chroot) is NOT supported: `dir-links.js`'s host-side
    resolution and `strace-spec.sh`'s hardcoded `/lib /lib64 /etc` finds both
    assume the traced system IS the build host.
  - gearmand on Rocky 9 needs **EPEL + CRB** (`gearmand` is in EPEL but pulls
    `libmemcached.so.11`, provided by `libmemcached-awesome` in CRB).
  - Two adapters when scripting the flow: drop **transient files** (gearmand's
    `/var/gearmand.pid`) from the parsed list before `dir-links` (it dies on any
    non-existent path); and write the rsync `--files-from` to a **real file**,
    not a `<(process substitution)`, because `sudo rsync` can't read the caller's
    `/dev/fd`.

**Remaining to call production-ready:**

- [ ] Use the **actual production worker source** (the bulk DNS resolver), not
      the demo `vzreverse`.
- [ ] Optionally trim the node base the same way.
- [ ] Promote the demo to a committable example (worker.js + 2-container pod) in
      `fleet.example/`, if useful — currently throwaway in `/tmp`.

## 2. Make bootstrap v3-aware — DONE

`bootstrap/bootstrap.yaml` now makes a fresh Rocky 9 node `vz apply`-ready via
`./bootstrap.sh <ip>` (connects as root, idempotent):

- [x] deploy user + passwordless sudo + key authorization (existing)
- [x] `dnf install podman skopeo` (node only runs/loads; `buildah` is build-host only)
- [x] `loginctl enable-linger <deploy-user>` (idempotent via the linger marker)

Validated on the clean Vultr Rocky 9 node: a re-run reports `ok=10 changed=0`,
i.e. it reproduces exactly the state proven by hand. Firewall is intentionally
not here — `vz apply` opens declared manifest ports (desired-state-driven).

## 3. Rocky-only build/control host

`vz apply` runs on a host with a local rootless Podman store. Today that is the
Alpine bootstrap host, which needed workarounds (vfs storage driver, manual
`/etc/subuid`+`/etc/subgid`, a `XDG_RUNTIME_DIR` export in `~/.profile`) because
its kernel has no `/dev/fuse`/overlay and no logind session. Its root disk is
also tiny (~2.7G), and vfs duplicates every layer, so the podman graphroot was
moved to a tmpfs (`/tmp`, RAM-backed) to fit a glibc gearmand image — fine while
RAM is free, but it evaporates on reboot. These are all **host-local, not in the
repo**, and all disappear on Rocky.

- [ ] Stand up the build/control host on Rocky 9 (overlay, subuid, logind all
      work out of the box — none of the Alpine workarounds needed).
- [ ] Capture its setup in a playbook so it is reproducible.
- [ ] Retire the Alpine host once migrated (it was only ever the small-ISO ESXi
      bootstrap host).

## 4. Update the front door — DONE

- [x] `README.md` now documents v3: invariants, the `fleet.example/` layout, the
      `bootstrap.sh → recipe.sh → vz validate/apply/ps/diff` workflow, the
      validated manifest subset, and Rocky 9-only nodes. The 2.x Ansible/`runch`
      workflow and RockyLinux 8 bootstrap are gone. No lab IPs/hostnames (public).

## Smaller follow-ups / known limitations

- [ ] `vz apply` and `vz ps`/`vz diff` query hosts **serially**; parallelize per
      host for larger fleets.
- [ ] `vz diff` checks the running pod, not whether the Quadlet `.kube` unit is
      installed/enabled. A node could be running-but-not-reboot-safe and look
      converged. Consider verifying the unit too.
- [ ] **Schema: one pod per host.** A host belongs to exactly one group, which
      runs one pod. Multiple pods per host would need a deliberate schema change
      (a list of pods per group) — not an accident.
- [ ] **Image transfer is whole-image** (`podman image scp`); the 2-layer split
      buys no WAN delta. If base sizes / deploy frequency ever make this bite,
      revisit the ephemeral SSH-tunnelled registry (rejected-alternatives note in
      `SPEC-v3.md`).
- [ ] **Firewall port management is additive only** — `vz apply` opens declared
      manifest ports but does not close ports removed from the manifest. Full
      reconciliation (close-stale) is a follow-up; `vz diff` could also report
      firewall drift.
- [ ] No design yet for **secrets / per-node config injection** into pods.
- [ ] `vztool` is run via `node src/*.ts` (node 24 strips types). No build/install
      step or `PATH` shims yet; add if it should be invokable as bare `vz-*`.

## Done (for reference)

- v3 spec + transport decision (`podman image scp`, with evidence).
- Manifest validator + node groups (`vztool/src/{schema,groups,validate}.ts`).
- `vzbuild oci.sh` (base/app/export), verified.
- `vz apply` (`vztool/src/{plan,apply,unit}.ts`).
- `vz ps` / `vz diff` (`vztool/src/{state,ps,diff}.ts`).
- Quadlet boot units; reboot survival verified on a real reboot.
