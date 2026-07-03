# vz

A distributed, independent cloud that runs Podman pods on low-RAM hosts.

- **cloud** — an API to deploy applications and allocate resources across more
  than one VPS.
- **distributed** — VPS from more than one vendor (⇒ reliable: a vendor can
  vanish overnight and take its servers with it).
- **independent** — command & control not owned by any VPS vendor (⇒ free as in
  freedom, not locked to one vendor).
- **low-RAM** — VPS cost is dominated by RAM, so small footprints mean cheaper.

## Why

With operating cost this low, even a hobbyist can afford to run a complex
multi-server web service for years. Cheaper VPS providers die often, so some
redundancy must be assumed — a VPS can disappear along with its hosting company
without notice, and vz's distributed, vendor-independent shape is the answer to
that. The hope: longer-lived hobbyist projects → more innovation on the web, at
half the entry cost.

## Non-goals

- Not a full Kubernetes replacement.
- Application-layer reliability (e.g. stuck queue jobs) is solved in the app, not
  by vz.

## v3 (current)

> The Podman-based line. `podman kube play` + Quadlet own the node; vz owns the
> *fleet* — desired state in git, whole-image push over SSH, and a fleet-wide
> view of drift (`vz apply`/`ps`/`diff`). The full design is in
> [`SPEC-v3.md`](SPEC-v3.md); remaining work is tracked in
> [`TASKS.md`](TASKS.md). The chroot/`runch`/`forever.sh` bring-up work is
> archived on the **`v2` branch**.

The bet of v3: **stop reinventing the node runtime.** `podman kube play` already
runs a pod from a Kubernetes-subset YAML, and systemd (via Quadlet) already
supervises it across reboots. So the node layer is *not our code* — vz's product
is the fleet layer `kube play` has no concept of: desired state, WAN image push,
and drift detection.

## Invariants

These carry over from the Roadmap and every part of v3 preserves them:

- **Sleeping plane / no management daemon.** Nodes run only `init`, `sshd`, and
  `systemd`. `podman kube play` is a one-shot command invoked over SSH, not a
  listening agent. There is no vz daemon on a node to attack.
- **Damage localization.** A node knows nothing about other nodes. No shared
  registry, no cluster membership. Desired state lives **only** on the control
  host. Compromising one node leaks nothing about the fleet.
- **WAN-first.** Everything assumes high-latency, lossy links. No consensus, no
  pull-from-registry. Images are *pushed*, minified, and layered.

## How it works

**Desired state is a git repo on the control host** — its history *is* the deploy
runbook. See [`fleet.example/`](fleet.example/) for a working layout:

```
fleet.example/
  groups.yaml          # topology: which hosts run which pod
  pods/
    antifraud.yaml     # a k8s-subset Pod manifest
  recipe.sh            # one build recipe that produces every fleet image
```

`groups.yaml` maps a named group of hosts to a pod manifest; a manifest
references images by tag (`image: localhost/gearmand:v3`); the recipe says how
those tags are built. Reading one pod file plus the recipe tells future-you both
*what runs* and *how to change it*.

The lifecycle is three steps — **bootstrap** a bare Rocky 9 node (`ansible/`
makes it `vz apply`-ready: deploy user, `podman`, rootless linger),
**build** images on the control host (rootless Podman + buildah), and **apply**
the fleet with `vz` (in [`vztool/`](vztool/)). `vz apply` is a thin wrapper: it
validates the fleet, generates an Ansible inventory, and runs the `podman-pod`
role, which `podman image scp`s images over SSH (no registry), installs each
manifest as a rootless Quadlet `.kube` unit (so pods restart on reboot), and
opens declared ports — all idempotent. **Ansible is the one executor across
bootstrap and deploy.** `vz diff` is the product surface: it tells you a node
rebooted and came back empty, or that a deploy half-applied.

The exact commands live in [`SPEC-v3.md`](SPEC-v3.md) and [`TASKS.md`](TASKS.md).
The ESXi/OVH way to *produce* nodes is a separate concern —
[`platform/ovh-esxi/`](platform/ovh-esxi/).

## The supported manifest subset

vz reuses the `podman kube play` subset rather than invent a schema, but
**validates** every manifest and **loudly rejects** any field it does not honor —
a field that looks supported but isn't is a hard error, never a silent ignore.
Notably:

- `imagePullPolicy: Never` is mandatory — vz uses what was pushed and never pulls.
- `image:` must be `localhost/...` — there is no registry.
- `ports: [{containerPort, protocol?}]` is honored, not cosmetic: with
  `hostNetwork: true` the container port is the host port, so the manifest is the
  single source of truth for what is reachable.

## Node platform

Nodes are **Rocky Linux 9 only** in v3. Everything needed comes from stock
appstream (`podman`, cgroups v2) with no third-party repos;
`bootstrap` installs it and enables rootless persistence. `buildah` and `skopeo`
are build-time tools and live on the control host (above), not the node. `vz apply`
runs on a control host with a local rootless Podman store.

## More

- **Build & minification** — how images are built and (optionally) minified:
  [`future/vzbuild/`](future/vzbuild/).
- **Positioning / prior art** — where vz sits relative to existing tools:
  [`COMPETITORS.md`](COMPETITORS.md).
