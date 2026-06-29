# vz [![Join the chat at https://gitter.im/nponeccop/vz](https://badges.gitter.im/nponeccop/vz.svg)](https://gitter.im/nponeccop/vz?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

A distributed independent cloud capable of running Podman pods on low RAM hosts.

- cloud := an API to deploy applications and allocate resources across more than one VPS
- distributed cloud := a cloud with VPS provided by more than one vendor
- independent cloud := a cloud with command & control system not controlled by VPS vendors (talk less locked to a single vendor)

Distibuted means reliable, independent means free as in freedom, low RAM means cheaper as the VPS cost is dominated by the RAM amount.

> **v3 (current):** the Podman-based line. `podman kube play` + Quadlet own the
> node; vz owns the *fleet* — desired state in git, whole-image push over SSH,
> and a fleet-wide view of drift (`vz apply`/`ps`/`diff`). The full design is in
> [`SPEC-v3.md`](SPEC-v3.md); remaining work is tracked in [`TASKS.md`](TASKS.md).
> The chroot/`runch`/`forever.sh` bring-up work is archived on the **`v2` branch**.

The bet of v3: stop reinventing the node runtime. `podman kube play` already runs
a pod from a Kubernetes-subset YAML, and systemd (via Quadlet) already supervises
it across reboots. So **the node layer is not our code** — vz's product is the
fleet layer `kube play` has no concept of: desired state, WAN image push, and
drift detection.

Invariants
----------

These carry over from the Roadmap and every part of v3 preserves them:

- **Sleeping plane / no management daemon.** Nodes run only `init`, `sshd`, and
  `systemd`. `podman kube play` is a one-shot command invoked over SSH, not a
  listening agent. There is no vz daemon on a node to attack.
- **Damage localization.** A node knows nothing about other nodes. There is no
  shared registry and no cluster membership. Desired state lives **only** on the
  master. Compromising one node leaks nothing about the fleet.
- **WAN-first.** Everything assumes high-latency, lossy links. No consensus, no
  pull-from-registry. Images are *pushed*, minified, and layered.

Layout of the desired state
---------------------------

A git repo on the master is the single source of truth; its history *is* the
deploy runbook. See [`fleet.example/`](fleet.example/) for a working layout:

```
fleet.example/
  groups.yaml          # topology: which hosts run which pod
  pods/
    antifraud.yaml     # a k8s-subset Pod manifest
  recipe.sh            # one build recipe that produces every fleet image
```

`groups.yaml` maps a named group of hosts to a pod manifest. A manifest
references images by tag (`image: localhost/gearmand:v3`); the recipe says how
those tags are built. Reading one pod file plus the recipe tells future-you both
*what runs* and *how to change it*.

Workflow
--------

**Configure the nodes** (once per node, from a bare Rocky 9 VPS with root + your
SSH key — e.g. straight from an activation email):

```shell
cd ansible && ./bootstrap.sh {server-ip}
```

This creates a deploy user named after you with passwordless `sudo`, installs
`podman`/`skopeo`, and enables `loginctl` linger so rootless pods survive logout
and come back on reboot. Idempotent — safe to re-run.

**Build the images** on the build/control host (rootless Podman + buildah):

```shell
sh fleet.example/recipe.sh        # minify -> oci.sh base/app -> localhost/<img>:v3
```

**Deploy and inspect the fleet** with `vz` (in [`vztool/`](vztool/), run via
node 24 which strips the TypeScript types — no build step):

```shell
node vztool/src/validate.ts fleet.example/groups.yaml   # reject unsupported fields, loudly
node vztool/src/apply.ts    fleet.example/groups.yaml   # scp images + manifests, install Quadlet unit, open ports
node vztool/src/ps.ts       fleet.example/groups.yaml   # fleet-wide actual running state
node vztool/src/diff.ts     fleet.example/groups.yaml   # desired (git) minus actual; exit 1 on drift
```

`vz apply` is a thin wrapper: it validates the fleet, generates an Ansible
inventory from `groups.yaml`, and runs `ansible/deploy.yaml` (the `podman-pod`
role). The role, per host, `podman image scp`s the pod's images over SSH (no
registry, and skips images already present), installs the manifest as a rootless
Quadlet `.kube` unit (so the pod restarts on reboot), (re)starts it via the user
systemd manager, and opens each declared `containerPort` in firewalld — all
idempotent, with real changed/ok reporting. Ansible is the one executor across
bootstrap and deploy (unified under [`ansible/`](ansible/)). `vz diff` is the
product surface — it tells you a node rebooted and came back empty, or that a
deploy half-applied.

The supported manifest subset
------------------------------

We reuse the `podman kube play` subset rather than invent a schema, but vz
**validates** every manifest and **loudly rejects** any field it does not honor —
a field that looks supported but isn't is a hard error, never a silent ignore.
Notably:

- `imagePullPolicy: Never` is mandatory — vz uses what was pushed and never pulls.
- `image:` must be `localhost/...` — there is no registry.
- `ports: [{containerPort, protocol?}]` is honored, not cosmetic: with
  `hostNetwork: true` the container port is the host port, so the manifest is the
  single source of truth for what is reachable (firewall, additive today).

Node platform
-------------

Nodes are **Rocky Linux 9 only** in v3. Everything needed is available from stock
appstream (`podman`, `skopeo`, `buildah`, cgroups v2) with no third-party repos;
`bootstrap` installs it and enables rootless persistence. `vz apply` runs on a
build/control host with a local rootless Podman store.

Why
---

with such low operation cost even a hobbyist can afford operating a complex multi-server web service for years. And I hope that such improved longevity of hobbyist projects will bring more innovations to the web, as entry cost is at least twice as lower.

One problem of using cheaper VPS providers is that many of them die each year. So some provisions for redundancy must be made,
as a VPS can just disappear along with its hosting company without any notice.

Non-goals
---------

- It's not a full k8s replacement.
- Application-layer reliability (e.g. stuck queue jobs) is solved in the app, not by vz.

Competitors
-----------
Rootfs:
- CoreOS
- RancherOS
- PhotonOS
- Ubuntu Snap
- RedHat Atomic
- Alpine Linux
- Intel Clear Linux

Container runners:
- docker/runc
- garden/warden
- Intel Clear Containers
- udocker/proot

Command and control:
- fleet/etcd
- kubernetes
- Heroku
- Dokku

Image building:

- Dockerfile/Docker build/buildkit
- smith
- s2i
- Heroku

Available Components
--------------------

### strace-trace (image minification)

`vzbuild` minifies a rootfs by tracing the program with `strace` and keeping only
the files it actually opens. `strace-trace` is the Linux-only tracer:

```shell
  $ strace-trace perl -MHTTP::Date -e 'print time2str(time())."\n"'
  $ cat spec
  /etc/localtime
  /usr/bin/perl
  /usr/lib/libc.so.6
  /usr/lib/libcrypt.so.1
  /usr/lib/libdl.so.2
  /usr/lib/libm.so.6
  /usr/lib/libpthread.so.0
  /usr/lib/locale/locale-archive
  /usr/lib/perl5/core_perl/CORE/libperl.so
  /usr/lib/perl5/core_perl/Config.pm
  /usr/share/perl5/core_perl/Carp.pm
  /usr/share/perl5/core_perl/Exporter.pm
  /usr/share/perl5/core_perl/Time/Local.pm
  /usr/share/perl5/core_perl/constant.pm
  /usr/share/perl5/core_perl/strict.pm
  /usr/share/perl5/core_perl/vars.pm
  /usr/share/perl5/core_perl/warnings.pm
  /usr/share/perl5/core_perl/warnings/register.pm
  /usr/share/perl5/vendor_perl/HTTP/Date.pm
```

The `spec` file is the input to building a minimal OCI rootfs. The minifier is
**same-system only**: install, trace, and build on one host (`ROOT=/`).
`oci.sh` then wraps the minified rootfs into a loadable OCI image.
