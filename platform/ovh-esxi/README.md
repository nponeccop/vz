# vz on OVH / ESXi — the ESXi adapter

## What this is

This folder turns a bare **OVH dedicated box running ESXi** into a supply of
clean, network-working Rocky VMs. It is the **ESXi adapter** for vz's handoff
contract (below) — the provider-specific plumbing that a normal VPS wizard would
do for you, but that OVH/ESXi makes you build yourself.

It is deliberately scoped as its own thing: a small **automated-homelab**
project whose first consumer is vz, but which is meant to be reusable for other
projects on the same box. Everything above the handoff contract — the fleet
layer, `podman kube play`, `vz apply`, the manifest subset, the sleeping-plane
security model — is **vz proper and lives elsewhere**:

- [`../../README.md`](../../README.md) — what vz is, for a newcomer.
- [`../../SPEC-v3.md`](../../SPEC-v3.md) — the v3 design.
- [`../../TASKS.md`](../../TASKS.md) — status, the genesis spike log, gotchas.

Read this file only if you are the **operator** standing up (or iterating on)
the ESXi box itself.

---

## The handoff contract — the boundary

Every adapter, on every provider, exists to produce exactly one thing:

> **a clean Rocky system, reachable as `root` over SSH with the deploy key
> authorized, on a working network.**

That is what a VPS provider hands you after its ordering wizard. Once the key is
present, **ansible takes over** and nothing above this line needs to know how the
VM was born. That seam is what keeps vz portable across ESXi, Vultr,
DigitalOcean, and bare-VPS providers with no cloud-init at all. (vz's control
plane is offline/NAT-isolated by design — the *sleeping-plane* model — but that
is a vz concern; see the global README.)

---

## Components

An adapter has two jobs: **acquire hosts** (order + inventory) and, where the
provider's own network doesn't just work, **inject per-VM config** (the
*seeder*). How much of each you need is provider-shaped:

- **Vultr adapter** ≈ nothing today. The ordering wizard *is* the adapter; DHCP
  and a public IP come for free. (A richer version could call Vultr's order API
  and return an inventory.)
- **OVH/ESXi adapter** = substantial, because OVH hands you a box on a *dead*
  network — no DHCP, and an extra public IP only routes to a provider-issued
  virtual MAC. So this adapter has two parts:

  1. **The seeder** *(first-class, core)* — stamps the golden image into a
     running, configured VM. This is where per-VM network + key injection
     happens. Required whenever the golden image alone can't produce a reachable
     box. See **[The seeder](#the-seeder)**.
  2. **The gateway / private network** *(optional)* — NAT + DHCP so a whole
     fleet can run behind a **single** public IP on **one** hypervisor. This is
     the cheap single-box config, and doubles as the fleet test harness. See
     **[A whole fleet on one box](#optional--a-whole-fleet-on-one-box)**.

How much the seeder must do is scenario-dependent and may shrink over time: a
private-net worker whose golden image already carries a DHCP client and
`open-vm-tools` needs almost no seed; a future 1-to-1 MAC-translation trick on
the gateway could make networking easier still.

---

## The seeder

`make-rocky-vm.sh` is the seeder: it clones the golden VMDK, builds a NoCloud
`CIDATA` seed ISO (key injection + optional network config), writes a VMX,
registers and boots the VM, and reports the IP once `root` SSH is up. It runs on
**any Linux that can SSH to ESXi** — the control host (at genesis, the transient
Alpine bootstrap host of the next section).

```sh
make-rocky-vm.sh NAME          # worker: DHCP on the Internal net, prints its IP
make-rocky-vm.sh -g NAME       # the gateway: static on both NICs (see optional section)
make-rocky-vm.sh -n -g NAME    # build + register but DON'T power on (genesis IP-handoff)
make-rocky-vm.sh -d NAME       # destroy (power off, unregister, delete)
```

The seed is **key-only by default** (root + the deploy key; networking is the
lab's job via DHCP). The one baked-in exception is `open-vm-tools`, which is
hypervisor-specific (ESXi needs the guest agent for IP reporting and graceful
shutdown) and so belongs to the *ESXi seed*, not to the provider-agnostic ansible
bootstrap.

**Disposable-VM loop** — the core iteration cycle once a gateway exists:

```sh
cp config.env.example config.env && $EDITOR config.env   # ESXI, datastore, subnet, PUB_*/OVH_MAC
ip=$(./make-rocky-vm.sh node1)        # clone golden -> DHCP worker; prints IP when root SSH is up
# run ansible against $ip, then:
./make-rocky-vm.sh -d node1           # tear it down
```

> **Note — the seeder has no per-worker-public-IP mode yet.** Today workers are
> DHCP-on-the-Internal-net (they need the gateway), and only the gateway itself
> gets a public IP. Giving each worker its own failover IP + virtual MAC (the
> scale-out / production direction below) is not yet a flag.

---

## Genesis — the first Linux host on a bare box (one-time)

The seeder needs a Linux host with `xorrisofs`; a freshly-installed ESXi box has
none, and you cannot make a guest without first running the seeder — a
chicken-and-egg. Genesis breaks it **without assuming any pre-existing Linux
machine**: boot a throwaway **Alpine live VM straight from its ISO** (no
installer, no seed) as the first Linux host. It borrows the failover IP just long
enough to build the real gateway, then is destroyed.

**What you need on your own machine:** a web browser, an SSH client, and one SSH
keypair — no Ansible, no local ESXi/OVH tooling, no build toolchain, no
pre-existing Linux box.

### 1. Generate a deploy key (workstation, once)

```sh
ssh-keygen -t ed25519 -C vz-deploy
```

The public half is the only secret the fleet ever holds. Put it at
`ansible/ssh.pub` in the repo.

### 2. Order + install the server (browser — OVH/Kimsufi manager)

- Order a Kimsufi / So-you-Start box and install the **ESXi** OS template,
  pasting your public key (or a root password) in the installer.
- Order **one additional/failover IP**, **generate its virtual MAC** (type
  `vmware`), and set its reverse DNS. This buy-an-IP + MAC-bind step is the one
  irreducible out-of-band action. *(`POST /dedicated/server/{sn}/virtualMac` via
  the API if you prefer; the CLI can manage but not order these.)*

### 3. Genesis part A — paste into ESXi's SSH

SSH to ESXi as `root`. Its BusyBox **`wget --no-check-certificate`** fetches over
HTTPS fine (no CA store, so verification is off — integrity comes from the pinned
**sha256**), so **no Python and no pre-staged files** are needed. This snippet
makes the isolated `Internal` vSwitch, fetches the golden VMDK + Alpine ISO,
imports the golden VMDK to a base disk, and boots an Alpine live VM on the
failover IP's virtual MAC:

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

### 4. Genesis part B — bring the bootstrap host online (browser: ESXi web console)

Open the `alpine-genesis` console, log in as `root` (empty password). The
failover IP is a `/32` whose gateway is off-subnet, so the default route must be
**on-link**. Then install your key and start sshd:

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

The console is fine for a single **paste** (miserable for *typing* a 400-char
key): run `ssh-add -L` on your workstation, copy the output, paste it into the
`cat >` above. That is the only manual transfer in the whole bootstrap.
(`ssh-copy-id`/agent-forwarding proved fragile through the web console — a plain
paste is what actually works.)

### 5. The bootstrap host builds the gateway, then hands off the IP

SSH to `root@<failover-IP>` — the first Linux machine. Install the small
toolchain and build the Rocky gateway from the golden image. Because the gateway
reuses the *same* failover IP/MAC, build it **without booting** (`-n`), then free
the IP and power the gateway on:

```sh
apk add git openssh xorriso bash
git clone <repo> vz && cd vz/platform/ovh-esxi
cp config.env.example config.env && vi config.env   # ESXI, DATASTORE, PUB_*/OVH_MAC, subnet
gwid=$(./make-rocky-vm.sh -n -g gateway)             # build + register, powered off
```

Hand the IP over **from your workstation** (not from the bootstrap host —
destroying the VM you're logged into would kill the command mid-run):

```sh
ssh root@<esxi> "\
  a=\$(vim-cmd vmsvc/getallvms | awk '\$2==\"alpine-genesis\"{print \$1}'); \
  vim-cmd vmsvc/power.off \$a; vim-cmd vmsvc/unregister \$a; \
  rm -rf /vmfs/volumes/<datastore>/alpine-genesis; \
  vim-cmd vmsvc/power.on <gwid>"          # <gwid> printed above
```

The Rocky gateway boots onto the failover IP with your key. From here **the
gateway is the control host**; install Ansible *there*, never on your laptop:

```sh
ssh root@<failover-IP>
dnf -y install git ansible-core
git clone <repo> vz && cd vz/ansible
ansible-playbook -i '<failover-IP>,' gateway.yaml   # NAT + DHCP for the Internal segment
```

Now the Internal segment has DHCP and a route out, so the handoff contract holds
for every future VM stamped by the seeder.

---

## Optional — a whole fleet on one box

The gateway + private network is the **cheap single-hypervisor** config: a whole
fleet of workers on `10.10.10.x` behind NAT, sharing **one** public failover IP.
This is what makes the "$17/mo, 32 GB / 2 TB, a whole fleet on one dedicated box"
pitch real, and it doubles as the **test harness** for exercising the mini-k8s as
a whole on a single box. It is genuinely optional — it exists because OVH is
IP-stingy — and may eventually move out of vz entirely (e.g. reused as a
general homelab controller, or extended with a WireGuard VPN into the private
net).

The gateway is stamped by the seeder's `-g` mode + configured by the ansible
`gateway` role:

- **`make-rocky-vm.sh -g`** — the one *static* seed. The gateway *is* the DHCP
  server, so it can't lease its own address: it gets a static NoCloud
  network-config v2 addressing both NICs (matched by pinned MAC, renamed
  `ext`/`int`), and a two-NIC VMX with the OVH virtual MAC on `ext`
  (`checkMACAddress = "FALSE"` so ESXi accepts the non-VMware OUI). It boots
  before any worker.
- **`ansible/gateway.yaml`** (role `ansible/roles/gateway`) — IPv4 forwarding +
  **nftables** NAT masquerade + **dnsmasq** internal DHCP. firewalld is retired
  on the gateway only (it would fight nftables); workers keep it.

**Scale-out / production alternative (direction, not yet built):** give each
worker its **own** failover IP + virtual MAC and drop the gateway entirely — the
same shape a normal VPS provider offers. This needs a new seeder mode (a static
public seed like the gateway's, minus the NAT/DHCP role) and per-worker OVH IP
orders. Not yet a flag.

---

## Operator reference

### This folder

| File | What it does | Runs on |
|------|--------------|---------|
| `make-rocky-vm.sh` | The **seeder**: create/destroy a Rocky VM over SSH-to-ESXi. `-g` = the static-network gateway; `-n` = build+register but don't boot (genesis IP-handoff) | any Linux that can SSH to ESXi — at genesis, the Alpine bootstrap host |
| `config.env.example` | Site config template — copy to `config.env` (gitignored) | — |
| `fix-ssh-agent.sh` | Re-point the shell at the rotated forwarded agent socket | control host |
| `../golden-image/build-golden-vmdk.sh` + `.github/workflows/golden-image.yml` | CI: build + publish the golden VMDK | GitHub Actions |
| `../../ansible/gateway.yaml` (role `roles/gateway`) | Make a booted clone the NAT/DHCP gateway | control host |

### config.env

Copy `config.env.example` → `config.env` (gitignored — never commit site
values). Keys: `ESXI`, `DATASTORE`, `PORTGROUP`, `BASE_VMDK`, `MEM`, `CPUS`,
`DISK` (grow root disk; empty = golden size); gateway adds `PUB_PORTGROUP`,
`OVH_MAC`, `PUB_ADDR`, `PUB_PREFIX`, `PUB_GW`, `PUB_DNS`, `INT_NET`, `INT_MAC`.

### The OVH CLI (ordering, IPs, reverse DNS)

OVH's API endpoint follows the **account's** OVH entity, not the server location.

1. Install: `curl -fsSL https://raw.githubusercontent.com/ovh/ovhcloud-cli/main/install.sh | sh`
   (lands in `~/.local/bin/ovhcloud` — add to `PATH`).
2. `ovhcloud login` — interactive; **needs a real TTY**. Writes `~/.ovh.conf`.
3. Pick the endpoint matching your account: `ovh-eu`, `ovh-ca`, `ovh-us`,
   `soyoustart-eu`, etc. If reads work but a write 404s, re-login against the
   other entity.
4. Verify: `ovhcloud account get` and `ovhcloud baremetal list`.

### Platform decisions

- **Rocky 9** is the target (well-trodden cloud image + cloud-init datasource);
  get the adapter flawless on 9 before Rocky 10.
- **Seeds are key-only** — networking is the lab's job (DHCP). The one exception
  is the gateway seed, which is static (it can't lease from itself).
- The **golden image is built in CI** and published as a pinned, sha256-verified
  release asset; the gateway is a clone of it driven by the ansible `gateway`
  role. This retired the old hand-installed Alpine "master" +
  `setup-master-*.sh` scripts. (Genesis status + the ESXi-fetch/CI spike log live
  in [`../../TASKS.md`](../../TASKS.md).)
```
