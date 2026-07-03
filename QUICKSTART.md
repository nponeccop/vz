# vz — Quickstart

Instruction-first companion to the design docs. **What** vz is and **why** it is
shaped this way live in [`README.md`](README.md) and [`SPEC-v3.md`](SPEC-v3.md);
remaining work in [`TASKS.md`](TASKS.md). This file is the ordered **how** — from a
bare machine to a running pod. The *decisions* behind each step live in
[`SPEC-v3.md`](SPEC-v3.md); this file links to the relevant section rather than
restating them.

## The two roles

vz has exactly two kinds of host. Everything below sets up one of each.

| Role | What it is | What runs on it |
|---|---|---|
| **Control host** | the operator's trust root: desired state, image builds, the dev cluster, and the deploy identity | git repo (the fleet), rootless `podman` + `buildah`, `vztool`, a local **k3s** (dev target), the hardware-key SSH identity |
| **Worker** | a "sleeping plane" node that only runs pods | `init` + `sshd` + `systemd` + `podman`; **no vz daemon** |

> **Why these two roles** — the control host as the operator's own offline
> workstation (the entire environment until you add workers), Rocky 9 only, one
> manifest / two backends (dev k3s vs. prod podman-over-SSH), and Ansible-over-SSH
> as the only control channel — is argued in [`SPEC-v3.md`](SPEC-v3.md): "Trust
> model", "Node platform", "Executors — one manifest, two backends", and the
> Invariants.

---

## 0. Control host — one-time setup

A Rocky 9 workstation or VM you control. Two playbooks make it vz-ready:

```sh
# (a) make THIS host a vz node: deploy user + podman + rootless linger
ansible-playbook -i '<control-host>,' ansible/bootstrap.yaml

# (b) add build + control tooling on top of (a)
./platform/ovh-esxi/buildhost.sh <control-host> <you>
```

Step (b) installs `buildah`/`skopeo`/`git`/`jq`/`rsync`, Node 24 (for `vztool`), the
`containers.podman` / `ansible.posix` / `kubernetes.core` collections, a
single-node **k3s** dev cluster (`--disable=traefik`), `~/.kube/config` pointed at
it, and a clone of this repo at `~/vz` with `vztool`'s npm deps.

> **Deploy identity.** Keep the fleet SSH key behind a hardware key (smart card /
> FIDO), agent-forwarded only for the length of a deploy; nodes get only its
> *public* half (`ansible/ssh.pub`). Why: [`SPEC-v3.md`](SPEC-v3.md) "Trust model".

---

## 1. The desired-state repo

Your fleet is a git repo — its history *is* the deploy runbook. Start from the
template:

```sh
cp -r fleet.example ~/fleet && cd ~/fleet && git init && git add -A && git commit -m init
```

- `groups.yaml` — topology: a named group → `{ hosts: [...], pod: pods/<x>.yaml }`
- `pods/*.yaml` — the k8s-subset Pod manifest each group runs
- `recipe.sh` — the one build recipe that produces every image

Layout and the "why two files" split (workload vs. placement):
[`fleet.example/README.md`](fleet.example/README.md).

> The manifest is a strictly-validated `podman kube play` subset —
> `imagePullPolicy: Never` and `localhost/...` images are mandatory. What's
> honored and why: [`SPEC-v3.md`](SPEC-v3.md) "Kubernetes YAML — a real, validated
> subset".

---

## 2. Simplest case — build + deploy to local k3s (no workers)

The whole dev environment on the one offline control host. No remote nodes, no
gateway.

```sh
cd ~/fleet

# validate the whole fleet (topology + every referenced pod)
node ~/vz/vztool/src/validate.ts groups.yaml

# build every image into the rootless podman store (recipe writes OCI to ./out/)
./recipe.sh

# apply to the local k3s dev cluster: import images (podman store -> k3s
# containerd), then apply the manifest with kubernetes.core.k8s
ansible-playbook -i <inventory> ~/vz/ansible/deploy-k3s.yaml
```

> **Status.** `vz apply` currently drives only the *prod* backend (§3); the dev/k3s
> path is run directly via `deploy-k3s.yaml` with the same generated inventory +
> per-host vars. A `--target podman|k3s` selector is tracked in TASKS
> "Fleet / `vz apply`". On the single-host dev setup the only node is the control
> host itself.

---

## 3. Add workers — the prod fleet

Prod is daemonless: images and manifests are pushed to each worker over SSH, and
systemd (via Quadlet) supervises the pod. Add workers when you want this backend.

1. **Produce Rocky 9 nodes** — any host reachable over SSH as root with the deploy
   key works. One turnkey way (a whole fleet behind one public IP) is the
   OVH/ESXi single-box platform — see §4.

2. **Bootstrap each node** (deploy user + `podman` + linger):

   ```sh
   ansible-playbook -i '<node>,' ansible/bootstrap.yaml
   ```

3. **List the node in your fleet** (`groups.yaml` → the group's `hosts`), then
   **build, push, and converge** from the control host:

   ```sh
   cd ~/fleet
   node ~/vz/vztool/src/validate.ts groups.yaml   # gate: stricter than podman
   ./recipe.sh                                     # build images
   node ~/vz/vztool/src/apply.ts   groups.yaml     # image scp + manifest, then kube play
   node ~/vz/vztool/src/ps.ts      groups.yaml     # fleet-wide actual state
   node ~/vz/vztool/src/diff.ts    groups.yaml     # desired (git) minus actual
   ```

> `vz apply` ships whole images with `podman image scp` (save|ssh|load) — no
> registry faces the fleet — and installs the manifest as a rootless **Quadlet**
> unit; `loginctl enable-linger` (done by bootstrap) keeps the pod alive past your
> SSH session and restarts it on reboot. `vz diff` then shows a node that rebooted
> empty or a half-applied deploy. Why: [`SPEC-v3.md`](SPEC-v3.md) "Image
> distribution", "Reboot survival", and "Commands".

---

## 4. Producing worker nodes (platforms)

Node production is a separate concern from the fleet layer above. Any Rocky 9 box
you can SSH into as root will do; vz doesn't care how it was made.

- **OVH / ESXi single box** — the cheap single-hypervisor config: a whole fleet of
  workers on a private Internal segment behind **one public IP**, served by a
  **gateway** VM (NAT + DHCP). The gateway is *only* part of this platform — it is
  not required for the §2 dev case. Full genesis (golden image → gateway →
  IP-handoff → worker seeding) and the `seed.yml`/`gateway.yaml` procedures:
  [`platform/ovh-esxi/README.md`](platform/ovh-esxi/README.md).

  > When workers sit on a private Internal net, run `vz apply` from a control host
  > that can route to that net (e.g. the gateway, or via it as an SSH jump host) —
  > the offline workstation reaches the public gateway, the gateway reaches the
  > workers.

---

## Where things live

| Doc | Purpose |
|---|---|
| [`README.md`](README.md) | what vz is, and the one-paragraph "how it works" |
| [`SPEC-v3.md`](SPEC-v3.md) | the design and the decisions behind it |
| [`TASKS.md`](TASKS.md) | what's left to do + hard-won lessons |
| [`fleet.example/`](fleet.example/) | canonical desired-state repo layout |
| [`platform/ovh-esxi/README.md`](platform/ovh-esxi/README.md) | producing nodes on OVH/ESXi (genesis, seeding, gateway) |
| [`future/vzbuild/`](future/vzbuild/) | image build + minification |
