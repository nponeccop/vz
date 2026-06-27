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

## Image distribution — push, not pull

`podman kube play` defaults to *pulling* `image:` from a registry. We disable
that (`imagePullPolicy: Never`) and pre-seed each node's local
`containers-storage`. Pipeline:

1. `vzbuild` minifies the rootfs (strace-driven, as in v2 — defended: WAN
   transfer is network-bound and a smaller attack surface is a goal).
2. **OCI-wrap** the minified rootfs into a loadable image
   (`buildah` / `podman build` `FROM scratch; COPY rootfs/`). This is new work:
   v2's bare `tar.xz` rootfs is not an OCI image and `kube play` cannot consume
   it.
3. Export as an OCI archive (`skopeo copy … oci-archive:`).
4. WAN-transfer the archive to the target nodes (over SSH).
5. On the node: `skopeo copy oci-archive:img.tar containers-storage:localhost/img:v3`.
6. `podman kube play node-x.yaml`.

### Two layers: base + app

Images are built in **two layers**, because the dominant change is "edit one
source file and redeploy":

- **base layer** — runtime + libraries (node.js, gearmand, etc.). Big, changes
  rarely, pushed once.
- **app layer** — the application source (`index.js` and friends). Tiny,
  changes often.

A source update ships **only the app layer**; Podman/skopeo dedup the unchanged
base blob. This keeps the minified attack surface *and* makes WAN updates cheap.

## Commands

- `vz apply` — render desired state from git; for each node, push any new image
  layers and the manifest, then run `podman kube play` (installed as a Quadlet
  unit so it persists). Replaces v2's imperative fire-and-forget Ansible push.
- `vz ps` — fleet-wide actual running state (queried live per node).
- `vz diff` — desired (git) minus actual (`vz ps`). **This diff is the product
  surface** — the thing that tells you a node rebooted and came back empty, or
  that a deploy half-applied.

## Reboot survival (lowest priority)

A Quadlet `.kube` unit in `/etc/containers/systemd/` is a systemd service;
systemd brings the pod up on boot. This *falls out* of the Podman swap rather
than being built — which is why it is last. Reboots happen quarterly and are an
annoyance, not an outage.

## Build order (by value, not by fun)

1. Desired-state in git: layout, fleet `recipe.sh`, manifest schema + validator.
2. `vzbuild`: OCI-wrap + 2-layer (base/app).
3. `vz apply`: layer-aware push + `podman kube play`.
4. `vz ps` + `vz diff`.
5. Quadlet boot units (mostly free once on Podman).

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
it is installed by default: bootstrap installs it (`dnf install podman skopeo
buildah`). The master remains close to distribution-agnostic.
