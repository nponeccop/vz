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

## Bootstrapping from zero (the operator's path)

**What you need on your own machine:** a web browser, an SSH client, and one SSH
keypair. That is *it* — **no Ansible, no local ESXi/OVH tooling, no build toolchain,
and no pre-existing Linux box.** Everything heavy (Ansible, the golden-image pipeline,
the fleet control loop) runs on hosts you create along the way; your workstation only
ever opens a browser and an SSH session. The barrier to entry is deliberately "can you
SSH and click a web UI".

**The one subtlety earlier drafts got wrong:** the toolchain that stamps VMs
(`make-rocky-vm.sh` → `xorrisofs`) needs a Linux host, and on a fresh box *there isn't
one yet*. We don't assume one — we boot a throwaway **Alpine live VM straight from its
ISO** (no installer, no seed) as the first Linux machine. It borrows the gateway's
failover IP just long enough to build the real (Rocky) gateway, then is destroyed.

The flow: **make a key → order + install ESXi (browser) → paste a genesis snippet into
ESXi's SSH (fetch images + boot the first Linux host) → paste your key into its console
→ let that host build the gateway → the gateway becomes the control host.**

### 1. Generate a deploy key (workstation, once)

```sh
ssh-keygen -t ed25519 -C vz-deploy
```

The public half is the *only* secret the fleet ever holds; the private half stays in your
agent / YubiKey (see the sleeping-plane model below). Put the public key at
`ansible/ssh.pub` in the repo.

### 2. Order + install the server (browser — OVH/Kimsufi manager)

- Order a Kimsufi / So-you-Start dedicated server and install the **ESXi** OS template,
  pasting your public key (or setting a root password) in the installer.
- Order **one additional/failover IP** for the gateway; **generate its virtual MAC**
  (type `vmware`) and set its **reverse DNS**. This is the one irreducible out-of-band
  step — an extra public IP must be bought and MAC-bound at the provider. *(The
  `ovhcloud` CLI can manage these but not order them; ordering is a manager/cart action.
  Virtual-MAC creation is `POST /dedicated/server/{sn}/virtualMac` if you prefer the API.)*

### 3. Genesis, part A — paste into ESXi's SSH

SSH to the ESXi host as `root`. ESXi's own BusyBox **`wget --no-check-certificate`**
fetches over HTTPS fine (it has no CA store, so verification is off and integrity comes
from the pinned **sha256**) — **no Python, no pre-staged files.** This snippet (a) makes
the isolated `Internal` vSwitch, (b) fetches the golden VMDK + the Alpine ISO, (c) imports
the golden VMDK to a base disk, (d) creates and boots an Alpine live VM on the failover
IP's virtual MAC:

```sh
DS=/vmfs/volumes/<datastore>
OVH_MAC=<OVH-virtual-MAC>            # from step 2
ALPINE_VERSION=3.21.0

# (a) isolated internal network (no uplink) — the workers' segment
esxcli network vswitch standard add -v vSwitch1
esxcli network vswitch standard portgroup add -p Internal -v vSwitch1

# (b) fetch golden VMDK + Alpine ISO (native wget; verify off + pinned sha256)
mkdir -p $DS/images $DS/iso
wget --no-check-certificate -O $DS/images/golden.vmdk "<release-asset-url>/Rocky-9-...-x86_64.vmdk"
echo "<pinned-sha256>  $DS/images/golden.vmdk" | sha256sum -c -
wget --no-check-certificate -O $DS/iso/alpine-$ALPINE_VERSION.iso \
  "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/x86_64/alpine-virt-$ALPINE_VERSION-x86_64.iso"

# (c) import golden to a thin base disk (cloned per VM thereafter)
vmkfstools -i $DS/images/golden.vmdk -d thin $DS/images/Rocky-9-base.vmdk

# (d) create + boot the Alpine bootstrap host on the failover IP's virtual MAC.
#     guestOS MUST be "other-64" (ESXi rejects "alpinelinux-64"); the pciSlotNumber /
#     pciBridge block is required or pvscsi can't get a PCI slot ("No PCIe slot for SCSI0").
mkdir -p $DS/alpine-genesis
vmkfstools -c 8G -d thin $DS/alpine-genesis/alpine-genesis.vmdk
cat > $DS/alpine-genesis/alpine-genesis.vmx <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "alpine-genesis"
guestOS = "other-64"
firmware = "efi"
numvcpus = "2"
memSize = "2048"
vmci0.present = "TRUE"
scsi0.present = "TRUE"
scsi0.virtualDev = "pvscsi"
scsi0.pciSlotNumber = "160"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "alpine-genesis.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"
sata0.present = "TRUE"
sata0.pciSlotNumber = "32"
sata0:0.present = "TRUE"
sata0:0.fileName = "$DS/iso/alpine-$ALPINE_VERSION.iso"
sata0:0.deviceType = "cdrom-image"
sata0:0.startConnected = "TRUE"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.pciSlotNumber = "192"
ethernet0.networkName = "VM Network"
ethernet0.addressType = "static"
ethernet0.address = "$OVH_MAC"
ethernet0.checkMACAddress = "FALSE"
ethernet0.startConnected = "TRUE"
svga.present = "TRUE"
svga.autodetect = "TRUE"
hpet0.present = "TRUE"
pciBridge0.present = "TRUE"
pciBridge0.pciSlotNumber = "17"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge4.pciSlotNumber = "21"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge5.pciSlotNumber = "22"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge6.pciSlotNumber = "23"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
pciBridge7.pciSlotNumber = "24"
EOF
vim-cmd vmsvc/power.on "$(vim-cmd solo/registervm $DS/alpine-genesis/alpine-genesis.vmx)"
```

### 4. Genesis, part B — bring the bootstrap host online (browser: ESXi web console)

Open the `alpine-genesis` VM console and log in as `root` (empty password). The failover
IP is a `/32` whose gateway is off-subnet, so the default route must be **on-link**. Then
install your key and start sshd — you're already root, so no extra user is needed:

```sh
# --- network: failover /32 with on-link gateway ---
ip addr add <failover-IP>/32 dev eth0
ip link set eth0 up
ip route add <gw> dev eth0            # <gw> = the .254 of the server's main /24
ip route add default via <gw>
echo nameserver 8.8.8.8 > /etc/resolv.conf
ping -c2 1.1.1.1                       # verify uplink

# --- your key + sshd ---
apk add openssh
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat > /root/.ssh/authorized_keys      # paste the line(s) from `ssh-add -L`, then Ctrl-D
chmod 600 /root/.ssh/authorized_keys
rc-update add sshd && service sshd start
```

The console is miserable for *typing* a 400-char key but fine for a single **paste**: run
`ssh-add -L` on your workstation (or `ssh-add -L > keys`), copy the output, and paste it
into the `cat >` above. That's the only manual transfer in the whole bootstrap. (The
slicker `ssh-copy-id`/agent-forwarding tricks proved fragile through the web console — a
plain paste of `ssh-add -L` is what actually works.)

### 5. The bootstrap host builds the gateway, then hands off the IP

SSH to `root@<failover-IP>` — the first Linux machine, born from an ISO with no prior
Linux box. Install the small toolchain and build the Rocky gateway from the golden image.
Because the gateway reuses the *same* failover IP/MAC, build it **without booting** (`-n`),
then free the IP and power the gateway on:

```sh
apk add git openssh xorriso bash
git clone <repo> vz && cd vz/platform/ovh-esxi
cp config.env.example config.env && vi config.env   # ESXI, DATASTORE, PUB_*/OVH_MAC, subnet
gwid=$(./make-rocky-vm.sh -n -g gateway)             # build + register the gateway, powered off
```

Now hand the IP over **from your workstation** (not from the bootstrap host — destroying
the VM you're logged into would kill the command mid-run):

```sh
ssh root@<esxi> "\
  a=\$(vim-cmd vmsvc/getallvms | awk '\$2==\"alpine-genesis\"{print \$1}'); \
  vim-cmd vmsvc/power.off \$a; vim-cmd vmsvc/unregister \$a; \
  rm -rf /vmfs/volumes/<datastore>/alpine-genesis; \
  vim-cmd vmsvc/power.on <gwid>"          # <gwid> printed above
```

The Rocky gateway boots onto the failover IP with your key (the handoff contract). From
here **the gateway is the control host**; you install Ansible *there*, never on your
laptop:

```sh
ssh root@<failover-IP>
dnf -y install git ansible-core
git clone <repo> vz && cd vz/ansible
ansible-playbook -i '<failover-IP>,' gateway.yaml   # NAT + DHCP for the Internal segment
```

Now the Internal segment has DHCP and a route to the internet, so the handoff contract
holds for every future VM. Stamp workers with `make-rocky-vm.sh nodeN` and manage them
with `bootstrap.sh` / `vz apply` — all from the gateway. The layers below detail each
piece; this section is the linear path through them.

---

## This folder

Tooling that stands up the lab and provisions Rocky VMs on OVH/ESXi.

| File | What it does | Runs on |
|------|--------------|---------|
| `make-rocky-vm.sh` | Create/destroy a Rocky VM over SSH-to-ESXi; `-g` = the static-network gateway, `-n` = build+register but don't boot (genesis IP-handoff) | any Linux that can SSH to ESXi — at genesis, the Alpine bootstrap host |
| `config.env.example` | Site config template — copy to `config.env` (gitignored) | — |
| `fix-ssh-agent.sh` | Re-point the shell at the rotated forwarded agent socket | control host |
| `../golden-image/build-golden-vmdk.sh` + `.github/workflows/golden-image.yml` | CI: build + publish the golden VMDK (Job A) | GitHub Actions |
| `../../ansible/gateway.yaml` (role `roles/gateway`) | Make a booted clone the NAT/DHCP gateway (Job B) | control host |
| ~~`setup-master-{sudo,nat,dhcp}.sh`~~ | *Legacy Alpine master scripts — superseded by the `gateway` role; kept until the real gateway boot is validated, then removed* | — |

**Quickstart** — see **[Bootstrapping from zero](#bootstrapping-from-zero-the-operators-path)** above for the full path. The disposable-VM loop for iterating on the bootstrap:

```sh
cp config.env.example config.env && $EDITOR config.env   # ESXI, datastore, subnet, PUB_*/OVH_MAC
ip=$(./make-rocky-vm.sh node1)        # clone golden → DHCP worker; prints IP when root SSH is up
# run ansible against $ip, then:
./make-rocky-vm.sh -d node1           # tear it down
```

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
  `setup-master-{sudo,nat,dhcp}.sh` shell scripts. **Nothing is ever *installed* from an
  ISO** — the only ISO booted anywhere is the Alpine *live* image that provides the
  disposable bootstrap host (it installs nothing and is thrown away).

- **Alpine is retired from *standing* infrastructure — but returns in one transient
  role.** No Rocky node ever runs Alpine, and no Alpine box stays up. But the genesis
  needs a *first Linux machine* to run `make-rocky-vm.sh` (which needs `xorrisofs`), and a
  fresh ESXi box has none — so genesis boots a throwaway **Alpine live VM straight from
  its ISO** (no installer, no seed) as that first host. It borrows the failover IP, builds
  the Rocky gateway (`make-rocky-vm.sh -n -g`), and is destroyed to free the IP. One OS
  (Rocky / RHEL-stable) for everything that *stays running*; Alpine is bootstrap-only.

**Getting the artifact onto ESXi (spiked ✅ — native `wget`).** Confirmed on ESXi 8.0.3
(BusyBox v1.29.3): **`wget --no-check-certificate` fetches HTTPS cleanly** — a 63 MB ISO
and the golden VMDK both pulled at exit 0. This *supersedes* the earlier "BusyBox wget
segfaults on TLS → use Python" finding, which was stale; **no Python is needed.** ESXi has
**no CA trust store** (`ca-certificates` absent), so verification is off and integrity
comes from the pinned **sha256**, exactly as the provenance design intended. The
`httpClient` firewall ruleset is already enabled; the datastore had 1.7 T free. SCP /
datastore-GUI upload remains the fallback if a box's outbound path is closed.

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

**Spike status (ESXi 8.0.3, all validated 2026-06-30):**
1. ✅ **confirmed** — the workflow built the VMDK in **~105 s** on a free public-repo
   runner (unmetered minutes) and published a **597 MB release asset** + sha256 (well
   under the 2 GB asset limit, so it never touches the artifact-storage quota).
2. ✅ **confirmed empirically** — a `qemu-img`-produced streamOptimized VMDK imported via
   `vmkfstools -i … -d thin` (*Clone: 100% → VMFS thin*, valid descriptor + geometry).
   Datastore 1.7 T free. Upload gotcha: ESXi needs **`scp -O`** (legacy protocol) — plain
   `scp` (OpenSSH 9 SFTP default) returns "Connection closed".
3. ✅ **confirmed (updated 2026-07-02)** — ESXi's BusyBox `wget --no-check-certificate`
   fetched 63 MB from an HTTPS mirror at exit 0; `httpClient` firewall already open. This
   *supersedes* the earlier python-only finding — BusyBox wget does **not** segfault on
   this box (v1.29.3), so **no Python path is needed**. **No CA store** → verify off +
   pinned sha256.
4. ✅ **validated on real hardware (2026-07-02)** — `make-rocky-vm.sh -g gateway` booted a
   golden clone with the failover IP + its virtual MAC on `ext` and `10.10.10.1` on `int`;
   the ansible **`gateway`** role brought up NAT + DHCP (`changed=0` on re-run — idempotent),
   and a worker regained internet through it. It replaced the Alpine master live.

**The gateway clone, as built.** `make-rocky-vm.sh -g` differs from a worker in three
places: the seed carries a NoCloud **network-config v2** that statically addresses both
NICs (matching each by its pinned MAC and renaming them `ext`/`int`); the VMX gives it
**two** vmxnet3 NICs — `ext` on the public portgroup pinned to the OVH virtual MAC with
`checkMACAddress = "FALSE"` (so ESXi accepts the non-VMware OUI), `int` on the Internal
portgroup; and the script skips the DHCP-lease wait, reaching the box at its known static
public IP. The ansible **`gateway`** role (`ansible/roles/gateway`, run via
`ansible/gateway.yaml`) then layers the gateway function — IPv4 forwarding, **nftables**
NAT masquerade, and **dnsmasq** internal DHCP — the RHEL-native replacement for the
Alpine `setup-master-{nat,dhcp}.sh`. firewalld is retired on the gateway only (it would
fight nftables for the ruleset); workers keep it.

**End-to-end proven with the real artifact (2026-06-30):** CI build → 597 MB release
asset → ESXi fetch (verify off; now via native `wget --no-check-certificate`) → **sha256
MATCH** → `vmkfstools -i … -d thin` → valid 10 G VMFS disk. The pipeline lives at `platform/golden-image/` +
`.github/workflows/golden-image.yml` (self-contained, for extraction to an image-only
repo).

**Whole chain proven on real hardware (2026-07-02).** CI golden image → ESXi import →
`make-rocky-vm.sh -g gateway` (failover IP + virtual MAC on `ext`, `10.10.10.1` on `int`)
→ ansible `gateway` role (NAT + DHCP, idempotent) → the Rocky gateway replaced the Alpine
master, and a worker regained internet through it. Two OVH-specific gotchas learned:
the failover IP is a **/32 whose gateway is off-subnet**, so the default route needs
`on-link` (netplan `to: 0.0.0.0/0`, **not** `to: default` — cloud-init 24.4 rejects the
`default` shorthand and voids the whole network-config); and the public NIC needs
`ethernet0.checkMACAddress = "FALSE"` for ESXi to accept the OVH virtual MAC. Alpine no
longer serves NAT/DHCP (moved to `10.10.10.2`, dnsmasq off); it remains only the
transitional operator/control host and is decommissioned once control moves onto the
gateway.

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
| 7 | **Golden image via CI** — `qcow2 → streamOptimized VMDK` pinned release artifact | 0 | **Done** — proven end-to-end on ESXi 8.0.3 | CI-quota spike ✅ |
| 8 | **Gateway = golden clone + ansible `gateway` role** (retires Alpine + `setup-master-*.sh`) | 0 | **Done** — booted on real HW 2026-07-02; replaced Alpine live | 7 + ESXi-fetch spike ✅ |

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
