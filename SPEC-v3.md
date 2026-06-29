# vz v3 — Specification

v3 is the Podman-based line. The chroot/`runch`/`forever.sh` bring-up work is
archived on the **`v2` branch**; `master` is v3 from here on.

The bet of v3: stop reinventing the node runtime. `podman kube play` already
runs a pod from a Kubernetes-subset YAML, and systemd (via Quadlet) already
supervises it across reboots. So **the node layer is not our code** — vz's
actual product is the *fleet* layer that `kube play` has no concept of:
desired state, WAN image push, and a fleet-wide view of drift.

## Invariants carried over from the Roadmap

These are not negotiable; every decision below preserves them.

- **Sleeping plane / no management daemon.** Nodes run only `init`, `sshd`, and
  `systemd`. `podman kube play` is a one-shot command invoked over SSH, not a
  listening agent. There is no vz daemon on a node to attack.
- **Damage localization.** A node knows nothing about other nodes. There is no
  shared registry and no cluster membership. Desired state lives **only** on the
  master. Compromising one node leaks nothing about the fleet.
- **WAN-first.** Everything assumes high-latency, lossy links. No consensus, no
  pull-from-registry. Images are *pushed*, minified, and layered so an update
  ships only what changed.

## Two layers

| Layer | Concern | Owner |
|---|---|---|
| Node | run a pod, supervise it, survive reboot | `podman kube play` + Quadlet (**not vz code**) |
| Build | minify rootfs → loadable OCI image | `vzbuild` |
| **Fleet** | **which node runs which pod (desired state)** | **vz — the product** |
| **Fleet** | **`vz apply`: push images + manifests over WAN** | **vz** |
| **Fleet** | **`vz ps` / `vz diff`: actual vs desired** | **vz** |

## Desired state lives in git

A git repo on the master is the single source of truth. Its history *is* the
deploy runbook: the answer to "why is this here / what did I change 6 months
ago" is `git log`. This serves the real use case — infrequent changes by an
operator who needs to *recall*, not a 24/7 reconciler.

Proposed layout:

```
fleet/
  recipe.sh            # one build recipe that produces every fleet image
  nodes/
    node-a.yaml        # k8s-subset pod manifest for node-a
    node-b.yaml
```

A manifest references images by tag (`image: localhost/dns-resolver:v3`); the
recipe says how those tags are built. Reading one node file plus the recipe
tells future-you both *what runs* and *how to change it* — closing the loop
that goes dark during deploys today.

## Kubernetes YAML — a real, validated subset

We reuse the `podman kube play` subset so we don't reinvent a schema, following
the precedent `podman kube play` itself sets. The trap is a format that *looks*
like k8s but silently no-ops 95% of PodSpec. So:

- vz **validates** every manifest and **loudly rejects** any field it does not
  honor. A field that looks supported but isn't is a hard error, never a
  silent ignore.
- `imagePullPolicy: Never` is mandatory on every container — vz uses what was
  pushed and must never attempt a registry pull.
- `ports: [{containerPort, protocol?}]` is **honored, not cosmetic**: `vz apply`
  opens each declared port in the node's firewall (firewalld). With `hostNetwork`
  the container port is the host port, so the manifest is the single source of
  truth for what is reachable — no manual `firewall-cmd`. (Additive today; it
  does not yet close ports removed from the manifest — see TASKS.)

## Image distribution — push, not pull

`podman kube play` defaults to *pulling* `image:` from a registry. We disable
that (`imagePullPolicy: Never`) and pre-seed each node's local
`containers-storage`. Pipeline:

1. `vzbuild` minifies the rootfs (strace-driven, as in v2 — defended: smaller
   attack surface, smaller first push, less disk on the node).
2. **OCI-wrap** the minified rootfs into a loadable image (`future/vzbuild/oci.sh`,
   rootless `buildah from scratch` + copy). This is new work: v2's bare `tar.xz`
   rootfs is not an OCI image and `kube play` cannot consume it.
3. Push the image to each target node with **`podman image scp`**.
4. `podman kube play node-x.yaml` on the node.

### Transport: `podman image scp` (whole image, no registry)

`podman image scp <image> <user>@<host>::` does `podman save | ssh | podman
load` — a whole-image transfer over plain SSH, no registry, no daemon, no
custom transfer code. This is the least-code transport and fits the sleeping
plane exactly (SSH is the only channel).

**Rejected alternatives, with the evidence:**

- *rsync of an OCI-layout directory* (hoping content-addressed blobs dedup for
  free): tested on bs-test and **refuted twice** — a one-file app edit re-shipped
  ~960KB of a 968KB image, compressed *and* uncompressed. OCI layer tar digests
  are not reproducible across builds (re-tarring varies mtimes/ordering), so the
  base layer looks new to rsync every deploy. Content-addressing only helps if
  the addresses are stable; skopeo-to-directory does not make them stable.
- *Ephemeral SSH-tunnelled registry* (the only thing that reliably ships just
  the changed layer, via registry HEAD-skip): real delta, but reintroduces a
  registry process. Deferred — not worth the complexity at our deploy cadence.

**Consequence for layering:** with whole-image scp, the 2-layer base+app split
buys **no transfer saving** — the base rides along on every deploy. `oci.sh`
still supports layering (it can speed local rebuilds), but the transport-delta
rationale is gone. For most pods a single minified image is simplest. The
trade-off we accept: an `index.js` edit re-ships the whole base. At our cadence
(infrequent, operator-driven redeploys, not CI) that is fine; if base sizes or
deploy frequency ever make the WAN cost bite, revisit the ephemeral registry.

## Commands

- `vz apply` — render desired state from git; for each host in each group,
  `podman image scp` the pod's images and copy the manifest, then run
  `podman kube play` (installed as a Quadlet unit so it persists). Replaces v2's
  imperative fire-and-forget Ansible push.
- `vz ps` — fleet-wide actual running state (queried live per node).
- `vz diff` — desired (git) minus actual (`vz ps`). **This diff is the product
  surface** — the thing that tells you a node rebooted and came back empty, or
  that a deploy half-applied.

## Reboot survival (implemented)

`vz apply` installs the manifest as a rootless Quadlet `.kube` unit in
`~/.config/containers/systemd/<pod>.kube` (beside `<pod>.yaml`); the systemd
generator turns it into `<pod>.service`, and with linger enabled the user
manager starts it on boot. Verified on bs-test: after a real reboot the pod
came back on its own and `vz diff` reported converged with no apply.

## Build order (by value, not by fun)

1. ✅ Desired-state in git: layout, fleet `recipe.sh`, manifest schema + validator.
2. ✅ `vzbuild`: OCI-wrap (+ optional 2-layer base/app).
3. ✅ `vz apply`: `podman image scp` push + Quadlet install.
4. ✅ `vz ps` + `vz diff`.
5. ✅ Quadlet boot units (folded into `vz apply`).

## What v2 retires

- `runch` (chroot runner), `forever.sh` (shell supervisor), and the jq
  `state.json` parsing → replaced by Podman + systemd.
- `vzmaster {push,start,kill}` → `vz {apply,ps,diff}`.
- `vzbuild` **survives**, gaining the OCI-wrap and 2-layer steps.

## Out of scope

- Application-layer reliability (e.g. stuck gearman jobs) — solved by proper
  queueing in the app, not by vz.
- Differential layer transfer (xdelta/bsdiff) — Podman blob dedup across the
  base/app split may already make this unnecessary; revisit only if measured WAN
  cost demands it.

## Node platform

Nodes are **Rocky Linux 9 only** in v3. Everything the node needs is *available*
from stock appstream (verified on Rocky 9.8: `podman` 5.8 — which bundles
Quadlet at `/usr/libexec/podman/quadlet` plus the systemd generator —
`skopeo` 1.22, `buildah` 1.43, cgroups v2), with no third-party repos. None of
it is installed by default; bootstrap installs it and enables rootless
persistence:

- `dnf install podman skopeo buildah`
- `loginctl enable-linger <user>` — **required**: rootless pods are owned by the
  deploy user's systemd manager. Without linger, closing the `vz apply` SSH
  session tears the pod down (observed: SIGKILL / exit 137). Linger keeps the
  user manager alive past logout and is also what lets the Quadlet boot units
  (step 5) start the pod on reboot.

**Where `vz apply` runs.** It needs the images in a local rootless `podman`
store, so it runs on a build/control host with `podman`/`buildah`. Today that is
the Alpine master (podman 5.8 with the `vfs` storage driver — the VM kernel has
no `/dev/fuse`/overlay, and `vfs` needs neither). The master remains close to
distribution-agnostic, but the long-term direction is **Rocky-only** (Alpine was
only ever the small-ISO ESXi bootstrap host); on Rocky the build host uses
overlay and none of the vfs/subuid/XDG workarounds are needed.
