# vz — Quickstart

Instruction-first companion to the design docs. **What** vz is and **why** it is
shaped this way live in [`README.md`](README.md) and [`SPEC-v3.md`](SPEC-v3.md);
remaining work in [`TASKS.md`](TASKS.md). This file is the ordered **how** — from a
bare machine to a running pod — with the decision behind each step pinned inline
so the instructions don't drift from the design.

## The two roles

vz has exactly two kinds of host. Everything below sets up one of each.

| Role | What it is | What runs on it |
|---|---|---|
| **Control host** | the operator's trust root: desired state, image builds, the dev cluster, and the deploy identity | git repo (the fleet), rootless `podman` + `buildah`, `vztool`, a local **k3s** (dev target), the hardware-key SSH identity |
| **Worker** | a "sleeping plane" node that only runs pods | `init` + `sshd` + `systemd` + `podman`/`skopeo`; **no vz daemon** |

> **Decision — the control host is the Admin's own Rocky Linux 9 workstation/VM,
> kept mostly offline / NAT-isolated.** It is the registry-and-etcd equivalent:
> desired state *and* images live only here. Keeping it off the network except
> during operator-initiated deploys shrinks the attack surface to the one secret
> that actually matters — the fleet SSH key. In the **simplest case this single
> offline host is the entire environment**: it builds images and runs the dev
> cluster locally, with *no workers and no gateway at all* (§2). You add workers
> only when you want the prod backend (§3). Rationale: SPEC-v3 "Trust model".

> **Decision — Rocky Linux 9 only, both roles.** Everything comes from stock
> appstream; no third-party repos land on a worker. (SPEC-v3 "Node platform".)

> **Decision — one manifest, two backends.** The same validated Pod manifest
> deploys to **dev** (k3s, on the control host itself) and **prod** (`podman` +
> systemd on workers, over SSH — no cluster plane to attack). Start with dev only.
> (SPEC-v3 "Executors — one manifest, two backends".)

> **Decision — Ansible is the only executor; SSH is the only channel.** Nothing
> listens on a worker; `podman kube play` is a one-shot command invoked over SSH,
> not an agent. (SPEC-v3 invariants.)

---

## 0. Control host — one-time setup

A Rocky 9 workstation or VM you control. Two playbooks make it vz-ready:

```sh
# (a) make THIS host a vz node: deploy user + podman/skopeo + rootless linger
ansible-playbook -i '<control-host>,' ansible/bootstrap.yaml

# (b) add build + control tooling on top of (a)
./platform/ovh-esxi/buildhost.sh <control-host> <you>
```

Step (b) installs `buildah`/`git`/`jq`/`rsync`, Node 24 (for `vztool`), the
`containers.podman` / `ansible.posix` / `kubernetes.core` collections, a
single-node **k3s** dev cluster (`--disable=traefik`), `~/.kube/config` pointed at
it, and a clone of this repo at `~/vz` with `vztool`'s npm deps.

> **Deploy identity.** The SSH key that reaches root on every node is the fleet's
> ultimate secret. Keep it behind a **hardware key** (smart card / FIDO) with
> human-in-the-loop confirmation, forwarded through your agent only for the length
> of a deploy. Nodes are seeded with its *public* half (`ansible/ssh.pub`); the
> private half never touches a node or the control host's disk.

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

> **Decision — a real, strictly-validated k8s subset.** vz reuses the
> `podman kube play` subset and **loudly rejects** any field it does not honor —
> never a silent no-op. `imagePullPolicy: Never` is mandatory (vz uses what was
> pushed, never pulls) and `image:` must be `localhost/...` (there is no runtime
> registry). (SPEC-v3 "Kubernetes YAML".)

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

2. **Bootstrap each node** (deploy user + `podman`/`skopeo` + linger):

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

> **Decision — push, not pull; whole image over SSH.** `vz apply` uses
> `podman image scp` (a `podman save | ssh | podman load`); no registry faces the
> fleet. (SPEC-v3 "Image distribution".)

> **Decision — reboot survival via Quadlet + linger.** The manifest is installed
> as a rootless Quadlet `.kube` unit, so the pod restarts on boot with no re-apply.
> `loginctl enable-linger` (done by bootstrap) is **required** — without it,
> closing the deploy SSH session SIGKILLs the pod. (SPEC-v3 "Reboot survival".)

> **`vz diff` is the product surface.** It tells you a node rebooted and came back
> empty, or that a deploy half-applied — the thing that goes dark during a deploy
> today.

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
