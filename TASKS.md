# vz v3 — remaining tasks

The v3 model is **proven end-to-end on a clean Rocky 9 node** (bootstrap → build →
`vz apply` → localhost colocation → external job round-trip → reboot-survives).
See [`SPEC-v3.md`](SPEC-v3.md) for the design.

## Direction (decided 2026-06-29) — Ansible is the first-class executor

The fleet plane was pivoted to **"B": the desired state *is* Ansible.** The old
`vz apply` shelled out to hand-rolled `ssh`/`scp`/`podman image scp`, which was a
regression from the core paradigm (SSH is the only control channel; Ansible is the
universal executor across *all* of the operator's projects). Now:

- **`vz apply` is a thin wrapper** (`vztool/src/apply.ts`): it validates the fleet,
  generates a YAML inventory (per-host `pod_name`/`pod_manifest`/`pod_images`/
  `pod_ports`), and runs `ansible-playbook deploy.yaml` against the `podman-pod`
  role. v2 did exactly this (`vzmaster.sh` → `ansible-playbook`); v3 restores it.
- **`vztool` keeps only its two unique jobs**: the **validator** (loud rejection of
  unsupported k8s fields — Ansible won't do this) and the diagnostic **`vz diff`**.
- The Ansible tree is **unified with bootstrap**: `bootstrap/` was renamed
  `ansible/` (one `ansible.cfg`, one `roles/`, one `ssh.pub`); it now holds
  `bootstrap.yaml` + `deploy.yaml` + `roles/{mivok0.sudo,podman-pod}`.

**Target model: one validated k8s-subset manifest, two executors.**

| | Executor | Control plane | Posture |
|---|---|---|---|
| dev/lab | `kubernetes.core.k8s` → **k3s** | real, bulky | insecure OK |
| staging/prod | `podman_play(quadlet)` over **SSH** (Ansible as "kubelet-by-SSH") | none — daemonless | lean, no attackable plane |

The validator is **one rule-set, two hats**: a continuous lint over the desired-state
repo *and* the CICD promotion gate. Inadmissible (prod-unhonorable) config is flagged
loudly, never silently dropped.

**Zero-trust gate for any future feature.** A new function is added only if
compromising vz's own control-plane infra yields nothing: registry → none today
(`podman image scp` over SSH from the offline control plane already is zero-trust);
state store → signed git + (later) sealed/at-rest-encrypted secrets.

## A. Ansible executor (the B pivot) — IN PROGRESS

- [x] `podman-pod` role: guarded `podman image scp` (skips images whose id already
      matches the node), `ansible.builtin.copy` manifest, `podman_play state: quadlet`
      to generate the `.kube` unit, `systemd_service scope: user` (re)start,
      `ansible.posix.firewalld` for declared ports.
- [x] `vz apply` rewritten as the inventory-generating wrapper; `buildInventory`
      unit-tested. Typecheck + 29 tests green.
- [x] Proven on the lab node: first run `ok=10 changed=2` (one-time — `podman_play`
      replaced the old hand-rolled `.kube`, triggering a restart; the guarded image
      scp correctly **skipped** both already-present images).
- [x] Full convergence confirmed: second run `ok=10 changed=0` (idempotent no-op).
- [ ] Migrate `vz ps`/`vz diff` query path off bespoke `state.ts` SSH? (Likely keep —
      the typed diff is the product; it is not Ansible's job.)
- [ ] Drop now-dead `vztool/src/unit.ts` + its test (`podman_play` generates the
      `.kube`; vz no longer owns that format).
- [ ] Silence the `INJECT_FACTS_AS_VARS` deprecation: use `ansible_facts['user_dir'|
      'user_id'|'user_uid']` instead of the bare `ansible_*` vars (also lets the
      `id -u` task be dropped — `ansible_facts.user_uid` gives the XDG uid).

## B. kubectl compatibility / dev k3s target — PROVEN, codification pending

- [x] **Two-target claim proven with one artifact.** The *same* `antifraud.yaml`
      runs on (1) daemonless podman over Ansible-SSH (prod, Vultr node) and (2) k3s
      on the ESXi build host: `podman save | k3s ctr images import` the localhost
      images, `kubectl apply` the manifest → pod `2/2 Running`, worker reached
      gearmand on `127.0.0.1`, external job round-trip OK.
- [ ] Codify the dev executor as a `kubernetes.core.k8s` play (image import task +
      apply), the dev-side analogue of `deploy.yaml` — currently done by hand
      (`k3s ctr images import` + `k3s kubectl apply`).
- [ ] Bring vz verbs/manifest "as close to kubectl as feasible" so k8s features can
      be added compatibly.

## C. Build & minify on k3s (control-plane-side k8s)

- [ ] Run build/minification as k8s **Jobs** on the dev k3s (ephemeral build pods;
      reproducible/CI-able). The minifier is currently host-bound (`sudo rsync`,
      `ROOT=/`) — containerizing it as a privileged build Job is the real lift.

## 1. The real workload — production-ready, blocked externally

The production shape (gearmand + node.js worker in one pod over `localhost`,
`hostNetwork: true`, rootless Podman) is fully proven. The DNS-resolver worker's
config is **baked into the image**, so no secrets machinery is needed to ship it.

- [x] node.js runtime through the whole pipeline; two-container pod via `vz apply`;
      worker reaches gearmand on `127.0.0.1`; full external job round-trip
      (scheduler → gearmand → in-pod worker → result).
- [x] gearmand minified the vz way (153MB → 21MB), verified in the pod.
- [ ] **Cutover is waiting on the prod environment getting a new server** (external,
      unrelated to vz). Use the real bulk-DNS-resolver worker source at cutover.
- [ ] Optionally trim the node base the same way.

  Minifier gotchas worth remembering:
  - Same-system only — install + trace + build on one host with `ROOT=/`. Tracing a
    foreign rootfs is unsupported (`dir-links.js` host-side resolution and
    `strace-spec.sh` hardcoded `/lib /lib64 /etc` finds assume traced == build host).
  - gearmand on Rocky 9 needs **EPEL + CRB** (pulls `libmemcached.so.11` from
    `libmemcached-awesome` in CRB).
  - Drop **transient files** (gearmand's `/var/gearmand.pid`) before `dir-links`;
    write the rsync `--files-from` to a **real file**, not `<(process substitution)`
    (`sudo rsync` can't read the caller's `/dev/fd`).

## 2. Bootstrap — DONE

`ansible/bootstrap.yaml` makes a fresh Rocky 9 node `vz apply`-ready via
`./bootstrap.sh <ip>` (deploy user + passwordless sudo + key, `podman`/`skopeo`,
`loginctl enable-linger`). Validated from scratch on the reinstalled Vultr node:
`ok=10 changed=5`; the deploy user confirmed `vz apply`-ready.

## 3. Rocky-only build/control host — IN PROGRESS

The decision: the build host becomes the **full control host** (ansible + git
desired-state + node/vztool + podman/buildah store + k3s). `vz apply` runs from it.
Alpine stays for now as the NAT/DHCP gateway and where the agent runs.

- [x] `buildhost` VM created on ESXi (Rocky 9.8, 4GB/2cpu, 40G via `DISK=`),
      bootstrapped (`ok=10 changed=5`), k3s installed (node Ready, v1.36.2+k3s1).
- [x] **Build-host control stack codified** in `platform/ovh-esxi/buildhost.yaml`
      (+`buildhost.sh`): buildah, git + cloned vz repo, Node 24 (NodeSource),
      ansible-core + collections (containers.podman/ansible.posix/kubernetes.core)
      + the `kubernetes` python lib (with the oauthlib pip-over-RPM fix), and k3s
      with the deploy user's kubeconfig. Clean-room validated via ESXi snapshot
      revert: `ok=12 changed=9 failed=0`, `kubernetes.core.k8s_info` SUCCESS.
- [ ] Move the desired-state repo + `vz apply` execution onto the build host
      (repo is cloned; still driving from Alpine for now).
- [ ] **ansible-core gap**: Rocky appstream ships ansible-core 2.14; vz runs fine
      on it so far, but newer collections may eventually want 2.15+. Revisit
      (pip/EPEL ansible-core) if a collection bumps its floor.
- [ ] Retire Alpine: redesign NAT/DHCP off it and **retest the ESXi bootstrap on a
      secondary clean ESXi host** before decommissioning.

## Smaller follow-ups / known limitations

- [x] ~~Serial host queries in `vz apply`~~ — Ansible forks parallelize the apply.
      (`vz ps`/`vz diff` still query serially in `state.ts`.)
- [ ] `vz diff` checks the running pod, not whether the Quadlet `.kube` unit is
      installed/enabled — a node could be running-but-not-reboot-safe and look
      converged.
- [ ] **Schema: one pod per host** — multiple pods per host would need a deliberate
      schema change (list of pods per group), not an accident.
- [ ] **Image transfer is whole-image** (`podman image scp`); revisit the ephemeral
      registry only if base sizes / deploy cadence make WAN cost bite.
- [ ] **Firewall close-stale**: the `firewalld` module *can* now remove ports
      (`state: disabled`), so full reconciliation is newly cheap — `vz apply` still
      only opens declared ports. Have the role close ports absent from the manifest;
      `vz diff` could report firewall drift.
- [x] ~~Secrets design~~ — **decided**: keyless nodes, **build-time / control-plane
      decryption** (ansible-vault/sops on the offline control plane while rendering
      the image/unit). Deferred until a workload needs it; a node-side `secretsd`
      for per-access audit is a later want.
- [ ] `vztool` is run via `node src/*.ts`. No build/install or `PATH` shims yet; add
      if it should be invokable as bare `vz-*`.

## Done (for reference)

- v3 spec + transport decision (`podman image scp`, with evidence).
- Manifest validator + node groups (`vztool/src/{schema,groups,validate}.ts`).
- `vzbuild oci.sh` (base/app/export), verified.
- `vz ps` / `vz diff` (`vztool/src/{state,ps,diff}.ts`).
- Quadlet boot units; reboot survival verified on a real reboot.
- README rewritten for v3.
