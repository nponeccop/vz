# Long-term vision

vz aims to be management middleware for **secure, libertarian, lightweight WAN
clusters** — the north star behind the concrete v3 design. This is the *why at
the horizon*; the invariants it commits us to are stated canonically (and kept
current) in [`SPEC-v3.md`](SPEC-v3.md), and the near-term pitch is in
[`README.md`](README.md).

## Secure cluster

### Damage localization

Once a system is compromised in one place, the design should stop the attack
from spreading further. CoreOS Fleet is the counter-example: hack one node and
the attacker gets the addresses of every other node and can install privileged
malware fleet-wide. vz keeps desired state **only on the control host**, so a
compromised node leaks nothing about the rest of the fleet.

### No management components to attack

Minimize the attack surface. Every cluster manager on the market exposes a
central manager — and often a node-side agent — to the attacker: a buffer
overflow or a vulnerable TLS stack in etcd, a centralized logging server,
monitoring/management agents on each node. vz nodes run only `sshd` and
`systemd`; there is no management daemon to attack.

vz does its management through **Ansible**, which is a glorified SSH executor: it
brings infrastructure-as-code management (idempotent, declarative, auditable)
while remaining **agentless**. There is no new listening service and no node-side
agent — the control channel is the SSH that was already there, so IaC management
costs *zero* extra attack surface.

## Kubernetes-friendly cluster

Kubernetes is the de-facto standard of private clouds, and fighting the standard
is a losing battle. vz aims to stay as close to Kubernetes' **file and
command-line syntax** as possible — pod manifests are a real, validated `podman
kube play` subset, not a look-alike schema — while implementing an *alternative
security model* underneath. The operator keeps k8s muscle memory and portable
manifests; vz swaps the exposed control plane (etcd, API server, node agents) for
the sleeping-plane, push-over-SSH model above. Familiar surface, different guts.

This rides tooling that Red Hat / IBM build and actively promote, so it stays
maintained without vz owning the node runtime: **Podman** — `podman kube play` +
Quadlet own the node, running a pod from k8s YAML and letting systemd supervise
it across reboots with no daemon to attack — and **Ansible** as the agentless
executor (see "No management components to attack" above).

## Libertarian cluster

A cluster resistant to shutdown by governments. Imagine a white-hat mirror set
(something WikiLeaks-like) spread across providers: with a CoreOS-style cluster,
once one node is discovered and imaged, all the others can be found and taken
down by confiscation orders to their respective providers. Damage localization
is exactly what prevents that — so this is really just a stronger form of the
same principle, not a purely anti-government feature. It serves mainstream,
security-savvy users just as well.

## Lightweight WAN cluster

All the management software on the market is designed for latency-free,
contention-free datacenters and fails when failover-consensus protocols — or
even message queues — run over WAN. But WAN distribution is essential for
disaster recovery and high availability: a service spread across regions or
providers. vz assumes WAN from the start — no consensus, no pull-from-registry; images are
*pushed*, not pulled, and minified. At the horizon: layering so an update ships
only what changed — a delta path still deferred today (see
[`SPEC-v3.md`](SPEC-v3.md), which is canonical on what actually ships now).

Lightweight is the other half. A small per-node footprint (low RAM, minified
images) keeps a complex multi-server service cheap enough for a single operator
to run for years — the affordability that makes the distributed, vendor-
independent shape practical rather than just principled.

And many small systems are still developed the traditional way: a single node,
where no scaling or failover ever happens in the background without an admin's
intervention. That makes Kubernetes' advanced run-time communication — the
consensus, service meshes, and reconcilers that watch for movement — redundant,
and it just burns precious RAM. Plenty of applications still subscribe to "start
the daemons once, run forever," with no movement in between. For them vz provides
system management through **Ansible**, which is agentless: the machinery runs
only when the admin invokes a change, and nothing sits resident consuming RAM the
rest of the time.
