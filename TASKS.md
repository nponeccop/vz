# vz v3 — remaining tasks

The v3 build order is **functionally complete** (see [`SPEC-v3.md`](SPEC-v3.md)):
desired state in git, `vzbuild oci` image wrap, `vz apply`, `vz ps`/`vz diff`,
and Quadlet boot units are all implemented in `vztool/` + `future/vzbuild/oci.sh`
and verified end-to-end on a Rocky 9 node (build → push → run → reboot-survives).

What is left is hardening and the real migration. Roughly in priority order.

## 1. Migrate the real workload (the actual proof)

Everything so far was proven with a single-container smoke pod. The real test is
the production shape: **gearmand + a node.js worker in one pod, talking over
`localhost`** (`hostNetwork: true`), under rootless Podman.

- [ ] Minify gearmand and the node.js runtime with the strace minifier
      (`future/vzbuild`: `strace-trace.sh` → `strace-spec.sh` → `from-spec.sh`),
      then `oci.sh base` each.
- [ ] `oci.sh app` to layer the worker source onto the node base.
- [ ] Write the real pod manifest + a `groups.yaml`; `vz-validate` it.
- [ ] `vz apply` and confirm the worker reaches gearmand on `127.0.0.1`
      (the localhost-colocation property; verify it holds rootless + hostNetwork).
- [ ] Confirm only the intended port is reachable from outside.

This is the thing that de-risks migrating production; until it works the model
is unproven for the target app.

## 2. Make bootstrap v3-aware

A freshly bootstrapped node must be `vz apply`-ready without manual steps. These
were done by hand during bring-up and need to land in the bootstrap playbook
(`bootstrap/`):

- [ ] `dnf install podman skopeo buildah`
- [ ] `loginctl enable-linger <deploy-user>` — **required**, or rootless pods are
      SIGKILLed when the deploy SSH session ends, and they will not start on boot.

## 3. Rocky-only build/control host

`vz apply` runs on a host with a local rootless Podman store. Today that is the
Alpine bootstrap host, which needed workarounds (vfs storage driver, manual
`/etc/subuid`+`/etc/subgid`, a `XDG_RUNTIME_DIR` export in `~/.profile`) because
its kernel has no `/dev/fuse`/overlay and no logind session. These are
**host-local and not in the repo**.

- [ ] Stand up the build/control host on Rocky 9 (overlay, subuid, logind all
      work out of the box — none of the Alpine workarounds needed).
- [ ] Capture its setup in a playbook so it is reproducible.
- [ ] Retire the Alpine host once migrated (it was only ever the small-ISO ESXi
      bootstrap host).

## 4. Update the front door

- [ ] `README.md` still documents the 2.x (Ansible/`runch`) workflow. Point it at
      v3 (`vz validate/apply/ps/diff`, Quadlet) and the `fleet.example/` layout.

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
