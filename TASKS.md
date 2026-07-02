# vz v3 — remaining tasks

The v3 model is **proven end-to-end on a clean Rocky 9 node** (bootstrap → build
→ `vz apply` → localhost colocation → external job round-trip → reboot-survives).
Design and the decisions behind it live in [`SPEC-v3.md`](SPEC-v3.md); this file
tracks only what's **left to do**, plus a Lessons section so hard-won gotchas
aren't re-learned.

## Open

### Fleet / `vz apply`

- [ ] Migrate the `vz ps`/`vz diff` query path off the bespoke `state.ts` SSH?
      (Likely keep — the typed diff is the product, not Ansible's job.)
- [ ] Bring vz verbs/manifest "as close to `kubectl` as feasible" so k8s features
      can be added compatibly.
- [ ] `vz apply` drives only the podman/prod backend (`deploy.yaml` → `podman-pod`);
      the dev/k3s executor (`deploy-k3s.yaml` → `k3s-pod`) exists but is run directly
      via `ansible-playbook` for now. Add a backend selector (`--target podman|k3s`)
      if `vz apply` should reach both, per SPEC "Executors — one manifest, two backends".

### Build & minify (the k8s build Job)

- [ ] Feed the recipe (`--base/--install/--trace/--out`) via env (`envFrom` a
      recipe ConfigMap — avoids YAML-quoting the install/trace strings); mount the
      `future/vzbuild` scripts via a ConfigMap at `/vzbuild` (defaultMode 0555).
- [ ] Output sink: on the single-node dev k3s a **hostPath** maps to the
      build-host fs (Job writes an `oci-archive`, host `skopeo copy`s it into
      podman/containerd). Blessed alt: a build-time registry on the control host.
- [ ] Make the build Job CI-able/reproducible; later drive it from
      `kubernetes.core.k8s`.

### Real workload (production cutover)

- [ ] **Blocked externally:** cutover waits on the prod environment getting a new
      server (unrelated to vz). Use the real bulk-DNS-resolver worker source at
      cutover. The production shape (gearmand + node worker in one pod over
      `localhost`, `hostNetwork: true`, rootless Podman) is already fully proven.
- [ ] Optionally trim the node base via the minifier (marginal win — see Lessons).

### Rocky-only control host + genesis

- [ ] Move the desired-state repo + `vz apply` execution onto the build host
      (repo is cloned; still driving from Alpine for now).
- [ ] ansible-core gap: Rocky appstream ships 2.14; vz runs fine on it, but
      revisit (pip/EPEL) if a collection bumps its floor past what works.
- [ ] Golden-image **provenance**: verify the artifact hash **off-ESXi** (at the
      workstation on upload, or the gateway once up) — never on ESXi.
- [ ] Golden-image **signing** (CI emits a sha256 today; a signature is TBD).
- [ ] **Rocky 10 generator** alongside the Rocky 9 golden image, for other ESXi
      projects (Rocky 9 stays the official vz bootstrap).
- [ ] **Retest the whole genesis on a secondary clean ESXi host** (ISO-boot
      bootstrap → `-n -g` gateway → IP handoff), then decommission Alpine from
      *standing* infra (it remains the transient ISO bootstrap host + a diagnostic
      image). Genesis procedure: `platform/ovh-esxi/README.md` "Genesis".

### Reconciliation gaps / limitations

- [ ] `vz diff` checks the running pod, not whether the Quadlet `.kube` unit is
      installed/enabled — a node can be running-but-not-reboot-safe yet look
      converged.
- [ ] `vz ps`/`vz diff` still query **serially** (`state.ts`); `vz apply` is
      already parallelized by Ansible forks.
- [ ] Schema is **one pod per host**; multiple pods per host needs a deliberate
      schema change (list of pods per group), not an accident.
- [ ] **Firewall close-stale:** the `firewalld` module can now remove ports
      (`state: disabled`), so have the role close ports absent from the manifest
      and have `vz diff` report firewall drift. Today `vz apply` only *opens*
      declared ports.
- [ ] Image transfer is whole-image (`podman image scp`); revisit the ephemeral
      registry only if base sizes / deploy cadence make WAN cost bite.
- [ ] **Image-signature hardening** (low priority — see SPEC "Trust model").
- [ ] **Secrets:** deferred until a workload needs it (approach decided — see
      SPEC "Trust model").
- [ ] `vztool` runs via `node src/*.ts`; no build/install or `PATH` shims yet —
      add if it should be invokable as bare `vz-*`.

## Lessons / gotchas (hard-won — don't re-learn)

### Minifier (`vzbuild`)

- **Same-system only:** install + trace + build on one host with `ROOT=/`.
  Tracing a foreign rootfs is unsupported (`dir-links.js` host-side resolution and
  `strace-spec.sh`'s hardcoded `/lib /lib64 /etc` finds assume traced == build
  host). The containerized `minify.sh` sidesteps this by making the *container* be
  the build host (rootless via `buildah unshare`).
- gearmand on Rocky 9 needs **EPEL + CRB** (`libmemcached.so.11` from
  `libmemcached-awesome` in CRB).
- Drop **transient files** (gearmand's `/var/gearmand.pid`) before `dir-links`;
  write the rsync `--files-from` to a **real file**, not `<(process
  substitution)` (`sudo rsync` can't read the caller's `/dev/fd`).
- A path opened via a **runtime bind mount** (`/etc/resolv.conf`, node's c-ares
  DNS) exists during `buildah run` but not in the static rootfs — filter strace
  candidates to those present in the mounted rootfs before `dir-links`, and let
  the runtime re-inject the rest.
- In a **privileged build pod**, skip `buildah unshare` when already `uid 0`: root
  with no `/etc/subuid` range makes unshare re-exec forever (the trailing
  `memfd_create(): Invalid argument` was noise from the loop, not a kernel issue —
  a red herring alongside the Fedora-crun `MFD_EXEC` kernel-≥6.3 dead end). Use
  `STORAGE_DRIVER=vfs`.
- **Traditional (declared-closure) builds** catch a missing runtime lib at *build*
  time via a chrooted smoke test — that's how we found gearmand needs
  `mariadb-connector-c` (pulled only via Recommends, dropped by
  `install_weak_deps=0`).

### Minifier size takeaways

The minifier's win is **workload-dependent** — huge for a fat-dependency daemon,
marginal for a self-contained binary + ICU (node). Measured the same day:

| image (x86_64)              | size    | notes                                       |
|-----------------------------|---------|---------------------------------------------|
| gearmand, vz minified       | 24.6 MB | strace closure of the running daemon        |
| gearmand, vz traditional    |  114 MB | full RPM closure (systemd, mariadb-c, etc.) |
| node v20, vz minified       |  104 MB | node binary + ICU dominate                  |
| node v20, vz traditional    |  107 MB | node binary + ICU dominate                  |
| `ubi9/nodejs-22-minimal`    |  256 MB | Red Hat's own "minimal" node runtime        |
| `rockylinux:9-ubi-micro`    | 21.9 MB | bare from-scratch EL9 userland (the floor)  |

gearmand-minified drags in none of the systemd/mariadb/tokyocabinet its RPM
closure pulls, landing ~4.6× smaller — essentially at the ubi-micro floor. node
is ≈3% either way (both styles must ship ICU), but still beats `nodejs-22-minimal`
~2.4× (scratch + `dnf --installroot` ships only node's closure, no base userland).

### OVH / ESXi genesis

- The failover IP is a **/32 whose gateway is off-subnet** → the default route
  must be **on-link** (netplan `to: 0.0.0.0/0`, **not** `to: default` —
  cloud-init 24.4 rejects the shorthand and voids the whole network-config).
- The public NIC needs `ethernet0.checkMACAddress = "FALSE"` for ESXi to accept
  the non-VMware OVH virtual MAC.
- ESXi's BusyBox `wget --no-check-certificate` fetches HTTPS fine — **no Python**.
  No CA store, so verify off + a pinned **sha256** for integrity.
- ESXi needs **`scp -O`** (legacy protocol); OpenSSH 9's SFTP default gets
  "Connection closed".
- Alpine genesis VMX: `guestOS = "other-64"` (ESXi rejects `alpinelinux-64`) + an
  explicit `pciSlotNumber`/`pciBridge` block, or pvscsi fails "No PCIe slot for
  SCSI0". Full recipe in `platform/ovh-esxi/README.md` "Genesis".

### Node runtime (v3 bring-up)

- `loginctl enable-linger` is **required**, or closing the `vz apply` SSH session
  SIGKILLs the rootless pod (exit 137). It is also what lets Quadlet boot units
  start the pod on reboot.
- `jshon` is dead upstream (absent from EPEL 9) → the node-side runtime was ported
  to **`jq`** (ships in Rocky baseOS).
- OCI layer tar digests are **not reproducible** across builds (re-tarring varies
  mtimes/ordering), which is why rsync-of-OCI-layout dedup was refuted — see SPEC
  "Image distribution".
