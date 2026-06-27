# vz bootstrap on OVH / ESXi — plan

## Why this exists

The real goal is to **resume work on an existing project whose deployment scheme is
fragile**, by making `vz` good enough to actually deploy it. `vz` today is unfinished and
unusable: the end-to-end bootstrap never ran cleanly — it always had to be pushed through by
hand, failing on bugs like referencing files that aren't there. Likely some code rot now that
Rocky 10 is current.

Everything else here is low-hanging fruit that's useful to others (and to us) even if only
partly finished:
- Mass-produce ansible-managed Rocky nodes on one Kimsufi/ESXi box ($17/mo, 32 GB / 2 TB) to
  consolidate all projects onto a single dedicated server.
- A reusable "Rocky anywhere" bootstrap that works on any provider, not just ESXi.

**Definition of done for the prize: `vz` can push an image to a freshly bootstrapped node.**
Not reboot-survival, not a running pod — a successful push.

---

## This folder

Tooling that stands up the lab and provisions Rocky VMs on OVH/ESXi.

| File | What it does | Runs on |
|------|--------------|---------|
| `setup-master-sudo.sh` | Passwordless sudo for a user (wheel group) | master, as root |
| `setup-master-nat.sh` | Master → NAT gateway on the Internal vSwitch | master, as root |
| `setup-master-dhcp.sh` | Master → DHCP server for the Internal vSwitch | master, as root |
| `make-rocky-vm.sh` | Create/destroy a Rocky 9 VM satisfying the handoff contract | master |
| `fix-ssh-agent.sh` | Re-point the shell at the rotated forwarded agent socket | master |
| `config.env.example` | Site config template — copy to `config.env` (gitignored) | — |

**Quickstart (once the master VM exists with the deploy key authorized):**

```sh
cp config.env.example config.env && $EDITOR config.env   # set ESXI, datastore, subnet
sudo ./setup-master-sudo.sh
sudo ./setup-master-nat.sh
sudo ./setup-master-dhcp.sh
# build the golden image once (see "golden image" in Layer 1), then:
ip=$(./make-rocky-vm.sh node1)        # prints the VM's IP when root SSH is up
./make-rocky-vm.sh -d node1           # tear it down
```

`make-rocky-vm.sh` is the disposable-VM loop for iterating on the bootstrap:
`ip=$(make-rocky-vm.sh n1)` → run ansible against `$ip` → `make-rocky-vm.sh -d n1`.

---

## The handoff contract

Every layer below the bootstrap exists only to produce one thing:

> **a clean Rocky system, reachable as `root` over SSH with the CAPI key authorized, on a
> working network.**

That is exactly what a VPS provider hands you. Once the key is present, **ansible takes over** —
nothing above this line needs to know how the VM was born. This is the seam that keeps the
design portable across ESXi, DigitalOcean, Vultr, and bare-VPS providers that offer no
cloud-init at all.

---

## Layers

### Layer 1 — VM provisioning → the handoff contract  ✅ validated
**ESXi-only for now; DigitalOcean / Vultr later. Bonus, not the prize.**

Produces a clean Rocky VM satisfying the handoff contract. The end-to-end flow has been proven
on ESXi (clean Rocky 9.8 VM, root SSH via CAPI key, DHCP address, internet via NAT).

The realized design:

- **Internal vSwitch + master as NAT/DHCP gateway.** VMs sit on an isolated `Internal`
  portgroup; the master bridges them to the internet. The master's internal NIC is the gateway
  (e.g. `10.10.10.1/24`) with `iptables` masquerade out the public NIC, IPv4 forwarding on, and
  `dnsmasq` serving DHCP on the internal range. **This is what makes the handoff contract real:
  a VM gets a working network the instant it boots, exactly like a VPS provider hands one over.**
- **Golden image, cloned per VM.** Download the Rocky cloud image once, convert `qcow2 →
  streamOptimized VMDK → VMFS thin` (qemu-img on a temporary scratch disk, since the master root
  fs is tiny; then `vmkfstools -i`). Keep the result as a read-only base and `vmkfstools -i`
  clone it per VM — no re-download/convert.
- **cloud-init seed = key-only (NoCloud ISO).** A tiny ISO labelled `CIDATA` with `meta-data` +
  `user-data` that injects the CAPI key for `root` and sets `PermitRootLogin prohibit-password`
  via an `sshd_config.d` drop-in. **No network-config** — DHCP from the master handles
  networking, which is simpler and provider-agnostic. cloud-init does **not** create users, sudo,
  or install packages — that's ansible's job, so the same ansible runs identically on a bare-VPS
  provider that has no cloud-init.
- Create the VM with `vim-cmd` (clone disk, write VMX, register, power on).
- Manual / OVH-API steps that stay out of band: ordering the server, ordering an extra IP,
  reverse DNS. (See OVH note below.)

**Gotchas learned the hard way (feed these into any automation):**
- The seed `user-data` **must be valid YAML** — one bad escape silently voids the *entire*
  cloud-config (cloud-init logs "empty cloud config" and applies nothing). Lint it with
  `python3 -c 'import yaml,sys; yaml.safe_load(...)'` before building the ISO.
- Guest NIC under Rocky 9 + vmxnet3 is **`eth0`**.
- **EFI + Secure Boot works** with Rocky 9 GenericCloud (signed shim/GRUB).
- A hand-rolled minimal VMX panics on `SVGA Framebuffer exceeds memory reservation`; copy a
  known-good template's SVGA settings (or `svga.present = "FALSE"` for headless) instead.
- Serial-to-file (`serial0.fileType = file`, Rocky logs to `ttyS0`) is the reliable way to read
  boot/cloud-init output on a headless VM — `vim-cmd vmsvc/screenshot` needs a framebuffer.

### Layer 2 — `bootstrap.sh` → manageable node  ✅ done
**ESXi-agnostic. This was the broken piece; it now runs clean and unblocks the prize.**

`bootstrap.sh` (a thin wrapper over `bootstrap.yaml`) takes a clean Rocky-with-key and makes
it a node `vzmaster` can drive: a deploy user in `wheel` with passwordless sudo and the key.

Fixed and verified on Rocky 9 (green + idempotent — 2nd run `changed=0`):
- `libselinux-python` (RHEL7-era, gone on Rocky 9/10) → **`python3-libselinux`**.
- Dropped the external `geerlingguy.repo-epel` galaxy role → native **`epel-release`** task
  (removes a fragility — no galaxy dependency at bootstrap time).
- Modernized modules (`ansible.builtin` / `ansible.posix`, `lookup('file', 'ssh.pub')`).
- Added `bootstrap/ansible.cfg` (host-key handling, `roles_path`) so runs don't prompt or
  depend on CWD quirks.

**The prize is met:** `make-rocky-vm.sh` → `bootstrap.sh <ip>` → `vzmaster push <image>` lands
an image `.txz` on the node (`vzmaster-push.yaml` now creates its image-store dir first;
`vzmaster/ansible.cfg` added). All three steps are green and idempotent.

### Layer 3 — podman ops under `vzmaster`
**ESXi-agnostic. The actual end the real project migrates onto.**

- `vzmaster push/start/kill` over SSH; image transfer over SFTP; node-local supervision via
  `runch`/`vzexec`.
- Debug podman/container builds (never done end-to-end before).
- Everything constrained by the sleeping-plane paradigm below.

---

## Sleeping-plane paradigm (security invariant)

**The control plane is dead whenever the admin is detached.** The master holds only *public*
keys; the CAPI *private* key lives in the admin's Windows cert store / YubiKey and is reachable
only via a live forwarded SSH agent with HITL confirmation (pageant + YubiKey touch). Think of
the forwarded agent as a smart card: present while working, gone on detach.

Consequences — we implement **only** what holds under this assumption:
- **No** autoscaling, failover, crash-rescheduling, or central monitoring. A node that dies at
  3am stays dead until the admin logs in.
- Features get re-imagined as **on-demand-over-SSH**, not 100%-uptime web panels — e.g. the
  admin pulls charts over SSH when attached.
- A **node-local supervisor is allowed** (restart a container on the same box), but it may
  **not** coordinate with other nodes — inter-node action is the control plane, which is
  forbidden while asleep.
- Monitoring is out of scope: the deployed app is observed by app-specific, out-of-band means.

This is still a lot — it's a declarative, apply-on-attach version of the
Kubernetes/Dokku/Heroku idea, minus the always-on controller.

---

## Access model — LLM-first iteration

The agent is given enough standing tooling to run a tight edit→provision→bootstrap→observe loop
without a human in every cycle.

| Surface | How the agent acts | Notes |
|---|---|---|
| ESXi root | Forwarded CAPI agent over SSH | Only while admin attached. Within the security model. |
| Scratch slave VM | `vim-cmd` create/destroy on `datastore1` | **Blessed disposable VM** — the core debug loop for Layer 2. Recreate at will. |
| OVH API | `ovhcloud` CLI, creds in `~/.ovh.conf` | **The one accepted-insecure surface.** OVH has no RSA/ECDSA-authenticated API to port onto an SSH agent, so there is no secure design. Touched **only during cluster changes** (order server/IP, reverse DNS), so it doesn't violate "offline control plane." |
| GitHub / CICD | `gh` CLI | Monitor CICD and push bootstrap fixes; commit identity comes from the authenticated user. |
| repo | git push | Fork or direct push, per the contributor's rights. |

**The accelerator:** the disposable scratch VM turns "rebuild the box by hand" into an
autonomous loop. That, plus `gh` for CICD feedback, is what makes iterating `bootstrap.sh` to
flawless actually fast.

### Setting up the OVH CLI (any OVH account)

OVH's API endpoint follows the **account's** OVH entity, *not* the physical server location.

1. Install: `curl -fsSL https://raw.githubusercontent.com/ovh/ovhcloud-cli/main/install.sh | sh`
   (installs to `~/.local/bin/ovhcloud` — add it to `PATH`).
2. `ovhcloud login` — interactive; **needs a real TTY** (won't run through Claude Code's `!`
   prefix, which has no `/dev/tty`). It generates the App Key / Secret / Consumer Key and writes
   `~/.ovh.conf`.
3. Pick the endpoint matching your account: `ovh-eu` (Europe), `ovh-ca` (Canada),
   `ovh-us` (US), `soyoustart-eu`, etc. If reads work but a later write 404s, the account may
   live on a different entity — re-login against the other endpoint.
4. Verify: `ovhcloud account get` and `ovhcloud baremetal list`.

---

## Workstreams, reprioritized

| # | Work | Layer | Priority | Blocker |
|---|------|-------|----------|---------|
| 1 | ~~Stand up disposable Rocky scratch VM on ESXi via cloud-init~~ | 1 | ✅ **done** — handoff contract validated end-to-end | — |
| 1b | ~~Script the VM-creation loop (`make-rocky-vm.sh`)~~ | 1 | ✅ **done** — one-command create/destroy, prints IP | — |
| 2 | ~~Fix + idempotent-ify `bootstrap.yaml`; debug to flawless~~ | 2 | ✅ **done** — green + idempotent on Rocky 9 | — |
| 3 | ~~Get `vzmaster push` to succeed end-to-end~~ | 3 | ✅ **done** — image lands on a freshly bootstrapped node | — |
| 3b | `vzmaster start`/`kill`: run a container via runch/vzexec under podman | 3 | **Next** — exercises the node-local supervisor | 3 done |
| 4 | Migrate the real project onto the new infra | — | The actual point | 3b done |
| 5 | Generalize Layer 1 to DigitalOcean / Vultr | 1 | Bonus | 2–3 stable |
| 6 | OVH API automation (order server/IP, reverse DNS) | 0 | Bonus | `ovhcloud` CLI configured |

---

## Decisions

- `gh` authenticated; OVH CLI configured (`~/.ovh.conf`).
- **Rocky 9** is the target — its cloud images and cloud-init datasource are well-trodden.
  Get the bootstrap flawless on 9 before considering Rocky 10.
- Direct push to the repo (no fork).
- **Networking by DHCP from the master**, not per-VM static cloud-init config. Simpler, and it
  matches the provider-handoff model (a VM just gets a working network on boot).
- **Seeds are key-only** — networking is the lab's job (DHCP), not the seed's.
