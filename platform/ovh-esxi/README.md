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

### Layer 0 — genesis: the golden image & the gateway  🔭 planned (redesign)

Layer 1 below assumes two things already exist: a **golden VMDK** to clone, and a
**gateway** running NAT/DHCP on the internal vSwitch. Producing those is the genesis
problem — and today it is the one part that is *not* automated. This layer fixes that.

**The chicken-and-egg.** The `qcow2 → VMDK` converter (`qemu-img`) needs a Linux host. On
a fresh ESXi box the only Linux host is a guest; but you cannot make a guest without a
template, and you cannot make a template without the converter. Today that loop is broken
by hand: a tiny Alpine ISO is uploaded from the admin workstation, installed as the
"master", and that Alpine guest runs *both* the converter (Job A) and the gateway (Job B).
The exact converter invocation was done once and **forgotten** — which is the whole
argument for automating it.

**The redesign — split the master's two jobs and delete one:**

- **Job A (image factory) moves off ESXi entirely.** Convert the Rocky GenericCloud
  `qcow2 → streamOptimized VMDK` in **CI**, and publish the result as a *pinned* release
  artifact. No converter ever runs on ESXi or on a lab guest, so the chicken-and-egg is
  dissolved and the cross-platform `qemu` pain (no Windows-friendly build) disappears. No
  custom compression is needed: a streamOptimized VMDK is already deflate-compressed and
  `vmkfstools -i` ingests it directly.
  - **Open — CI quota.** A multi-GB convert plus a ~600 MB artifact may exceed free
    GitHub Actions runner/artifact limits. Measure before committing; fallbacks are a
    self-hosted runner, GitLab CI, or a one-off local build attached as a release.

- **Job B (gateway) becomes a clone of the golden image.** Once ESXi can obtain the
  golden VMDK, the gateway is just an early clone, configured by an ansible **`gateway`
  role** (NAT + `dnsmasq` DHCP + the future HTTPS reverse proxy) that replaces the
  `setup-master-{sudo,nat,dhcp}.sh` shell scripts. No installer ISO is ever booted again.

- **Alpine is retired from infrastructure.** Its only advantage was a tiny install ISO;
  the golden-clone genesis boots *no* installer ISO at all, so that advantage evaporates.
  Alpine survives only as a hand diagnostic image — one OS (Rocky / RHEL-stable) for all
  lab infrastructure.

**Getting the artifact onto ESXi (unconfirmed — spike first).** Either ESXi's busybox
`wget`/`curl` TLS-fetches the pinned artifact directly, or — if its TLS stack is too old —
the admin uploads it once per physical box via SCP / datastore GUI. That upload is
one-time per server rental (rare), so the SCP fallback is acceptable even if it is not
pretty.

**The gateway is the one special seed.** Every worker keeps the proven key-only + DHCP
seed. The gateway cannot get an address from a DHCP server that is *itself*, so it needs a
**static** seed: a static internal IP (e.g. `10.10.10.1/24`), the OVH public IP, and —
because OVH routes an extra IP only to its assigned **virtual MAC** — a hardcoded
`ethernet0.address` (not ESXi's `addressType = "generated"`). It must boot **before** any
worker. The OVH side (buy IP, generate virtual MAC, reverse DNS) stays the one accepted
out-of-band manual step, same category as the OVH API.

**Provenance (fixing a bad habit).** The golden image seeds *every* node, so a tampered or
truncated artifact would silently become the base of the whole fleet. CI emits a sha256
(and ideally a signature); it is verified **off-ESXi** — at the workstation on upload, or
on the gateway once it is up — never on ESXi's limited shell, so there is no "verify on
ESXi" chicken-and-egg. Cheap, and it removes the "we never checked the ISO" habit.

**Spike before any code (the redesign rests on unconfirmed ESXi capability):**
1. CI can build the VMDK within quota (or pick a fallback runner).
2. `vmkfstools -i` imports a *CI-produced* streamOptimized VMDK and it boots.
3. ESXi can TLS-fetch the artifact (else SCP / GUI upload).
4. A Rocky golden clone comes up as a working static-network gateway from the new seed.
   (Clone + seed + cloud-init is already proven by `make-rocky-vm.sh`; only the
   static-gateway seed variant is new.)

---

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
  clone it per VM — no re-download/convert. *(This manual on-master converter is being
  retired — see Layer 0: the VMDK is built in CI and published as a pinned artifact.)*
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

### Layer 3 — container ops under `vzmaster`  ✅ start/kill working (chroot runtime)
**ESXi-agnostic. The actual end the real project migrates onto.**

The full lifecycle now runs end to end on Rocky 9 (verified with a static-busybox smoke
bundle): `vzmaster push` → `start` → `kill`.

- `push` copies the image `.txz`; `start` unpacks it, deploys `runch`/`forever`/`vzexec`,
  and launches the container under the `forever` supervisor; `kill` tears down the process
  group (supervisor included — no respawn) and cleans mounts + state.
- `runch` is currently a chroot-based OCI-bundle runner. **Podman is still on the roadmap** as
  the real runtime (with `runc` as the other substitution target); the chroot runner is the
  bring-up path, not the destination.
- Everything constrained by the sleeping-plane paradigm below.

**The Rocky 9 fix that mattered:** `jshon` is dead upstream (absent from EPEL 9). The
node-side runtime (`runch`, `kill.sh`, the start playbook) was ported to **`jq`** (ships in
Rocky baseOS). The `forever` supervisor is launched via ansible `async`/`poll: 0` so the
connection detaches instead of hanging on the backgrounded process.

**Known follow-ups (latent, not blocking):**
- Swap the chroot runner for **Podman** (roadmap) — `runch`'s start/kill contract stays, the
  backend changes.
- `vzmaster.sh` still uses `jshon` to *build* JSON, but that runs on the master (Alpine, where
  jshon is installed). Port to `jq` for consistency since jshon is unmaintained.
- `forever` is a shell supervisor; a systemd/rc.d unit would be a sturdier node-local
  supervisor and fits the sleeping-plane model.
- The smoke-test bundle is gitignored (binary rootfs); a small build script would make it a
  committable fixture.

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
| 3b | ~~`vzmaster start`/`kill`: run a container via runch/vzexec~~ | 3 | ✅ **done** — full push→start→kill lifecycle on Rocky 9 (chroot runtime) | — |
| 3c | Swap chroot runner for Podman | 3 | Roadmap — real runtime behind runch's contract | — |
| 4 | Migrate the real project onto the new infra | — | **Next** — the actual point | 3b done |
| 5 | Generalize Layer 1 to DigitalOcean / Vultr | 1 | Bonus | 2–3 stable |
| 6 | OVH API automation (order server/IP, reverse DNS) | 0 | Bonus | `ovhcloud` CLI configured |
| 7 | **Golden image via CI** — `qcow2 → streamOptimized VMDK` pinned release artifact | 0 | **Planned** — retires the forgotten on-master converter | CI-quota spike |
| 8 | **Gateway = golden clone + ansible `gateway` role** (retires Alpine + `setup-master-*.sh`) | 0 | **Planned** — fully automated genesis | 7 + ESXi-fetch spike |

---

## Decisions

- `gh` authenticated; OVH CLI configured (`~/.ovh.conf`).
- **Rocky 9** is the target — its cloud images and cloud-init datasource are well-trodden.
  Get the bootstrap flawless on 9 before considering Rocky 10.
- Direct push to the repo (no fork).
- **Networking by DHCP from the master**, not per-VM static cloud-init config. Simpler, and it
  matches the provider-handoff model (a VM just gets a working network on boot).
- **Seeds are key-only** — networking is the lab's job (DHCP), not the seed's. *(One
  exception, by necessity: the **gateway** seed is static — it is the DHCP server and
  cannot lease from itself. See Layer 0.)*
- **Genesis is automated via a CI-built golden image (planned).** The `qcow2 → VMDK`
  converter moves to CI and publishes a pinned, hash-verified artifact; the gateway
  becomes a clone of that image driven by an ansible `gateway` role. This **retires
  Alpine** from infrastructure (kept only as a diagnostic image) and the
  `setup-master-*.sh` shell scripts. Gated on a CI-quota + ESXi-fetch spike (Layer 0).
