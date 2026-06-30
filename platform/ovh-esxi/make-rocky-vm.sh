#!/bin/sh
# make-rocky-vm.sh — create (or destroy) a Rocky 9 VM on ESXi that satisfies the
# vz handoff contract: clean Rocky, root reachable over SSH with the deploy key,
# networking via the lab's DHCP (master = NAT/DHCP gateway on the Internal vSwitch).
#
# Usage:
#   make-rocky-vm.sh NAME            create worker VM NAME (DHCP), print its IP
#   make-rocky-vm.sh -g NAME         create the gateway VM NAME (static both NICs)
#   make-rocky-vm.sh -d NAME         destroy VM NAME (power off, unregister, delete)
#
# Gateway mode (-g) builds the one special seed: the always-on NAT/DHCP box. It IS
# the DHCP server, so it cannot lease its own address — it gets STATIC networking
# on both NICs, with the public NIC pinned to the OVH virtual MAC. It must boot
# before any worker. See README "Layer 0".
#
# Configuration: ./config.env (gitignored) overrides the defaults below.
# See config.env.example. Key vars: ESXI, DATASTORE, PORTGROUP, BASE_VMDK, MEM,
# CPUS, DISK (grow root disk; empty = golden image size). Gateway adds:
# PUB_PORTGROUP, OVH_MAC, PUB_ADDR, PUB_PREFIX, PUB_GW, PUB_DNS, INT_ADDR,
# INT_CIDR, INT_MAC.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Precedence: explicit environment > config.env > built-in defaults. Capture any
# caller-set vars first, source config.env, then re-apply the caller's values so
# `MEM=4096 CPUS=2 DISK=40G make-rocky-vm.sh ...` is not clobbered by config.env.
for __v in ESXI DATASTORE PORTGROUP BASE_VMDK SSH_PUB LEASES MEM CPUS DISK WORK; do
  eval "__env_$__v=\${$__v+x}"; eval "__envval_$__v=\${$__v:-}"
done
[ -f "$SCRIPT_DIR/config.env" ] && . "$SCRIPT_DIR/config.env"
for __v in ESXI DATASTORE PORTGROUP BASE_VMDK SSH_PUB LEASES MEM CPUS DISK WORK; do
  eval "[ -n \"\${__env_$__v}\" ] && $__v=\${__envval_$__v}" || true
done

ESXI=${ESXI:-root@esxi.example.net}
DATASTORE=${DATASTORE:-/vmfs/volumes/datastore1}
PORTGROUP=${PORTGROUP:-Internal}
BASE_VMDK=${BASE_VMDK:-$DATASTORE/images/Rocky-9-base.vmdk}
SSH_PUB=${SSH_PUB:-$SCRIPT_DIR/../../ansible/ssh.pub}
LEASES=${LEASES:-/var/lib/misc/dnsmasq.leases}
MEM=${MEM:-2048}
CPUS=${CPUS:-1}
# DISK: grow the cloned root disk to this size (e.g. 40G) before first boot, so
# the Rocky cloud image's cloud-init growpart extends root to fill it. Empty =
# keep the golden image's size (10G). Accepts vmkfstools -X sizes (G/K/m...).
DISK=${DISK:-}
WORK=${WORK:-${TMPDIR:-/tmp}/ovh-esxi-seeds}

# -- gateway (-g) mode: the always-on NAT/DHCP box. Static on both NICs (it is the
# DHCP server, so it can't lease its own address). The public NIC carries the OVH
# virtual MAC (bought + generated at the provider — the accepted out-of-band step);
# checkMACAddress=FALSE lets ESXi accept that non-VMware MAC. The seed matches each
# NIC by MAC and renames them ext/int, so the gateway role gets stable names.
PUB_PORTGROUP="${PUB_PORTGROUP:-VM Network}"  # public uplink portgroup
OVH_MAC=${OVH_MAC:-}                          # OVH virtual MAC for the public NIC
PUB_ADDR=${PUB_ADDR:-}                        # public IP of the gateway
PUB_PREFIX=${PUB_PREFIX:-24}                  # public prefix length
PUB_GW=${PUB_GW:-}                            # provider gateway (default route)
PUB_DNS=${PUB_DNS:-8.8.8.8}                   # resolver for the gateway itself
INT_ADDR=${INT_ADDR:-10.10.10.1}             # gateway's Internal-side address
INT_CIDR=${INT_CIDR:-10.10.10.0/24}          # Internal network (prefix taken from here)
INT_MAC=${INT_MAC:-00:50:56:10:10:01}        # Internal NIC MAC (VMware OUI range)
GATEWAY=0
# MACs lowercased for deterministic cloud-init `match: macaddress`.
OVH_MAC=$(printf '%s' "$OVH_MAC" | tr 'A-Z' 'a-z')
INT_MAC=$(printf '%s' "$INT_MAC" | tr 'A-Z' 'a-z')

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo ">> $*" >&2; }

# -- Use the forwarded deploy-key agent; pick the first socket that has keys --
ensure_agent() {
  if [ -n "${SSH_AUTH_SOCK:-}" ] && ssh-add -l >/dev/null 2>&1; then return; fi
  for s in $(ls -t "$HOME"/.ssh/agent/s.* /tmp/ssh-*/agent.* 2>/dev/null); do
    if SSH_AUTH_SOCK="$s" ssh-add -l >/dev/null 2>&1; then
      export SSH_AUTH_SOCK="$s"; return
    fi
  done
  die "no working SSH agent socket (is the agent forwarded?)"
}

# -q suppresses the host's post-quantum KEX banner; accept-new avoids first-contact prompts
esxi() { ssh -q -o StrictHostKeyChecking=accept-new "$ESXI" "$@"; }

# ---------------------------------------------------------------- destroy
destroy_vm() {
  NAME=$1
  log "destroying $NAME"
  vmid=$(esxi "vim-cmd vmsvc/getallvms 2>/dev/null | awk -v n=$NAME '\$2==n{print \$1}'")
  if [ -n "${vmid:-}" ]; then
    esxi "vim-cmd vmsvc/power.off $vmid 2>/dev/null; vim-cmd vmsvc/unregister $vmid" || true
  fi
  esxi "rm -rf $DATASTORE/$NAME $DATASTORE/images/$NAME-seed.iso"
  log "destroyed $NAME (DHCP lease will expire on its own)"
}

# ---------------------------------------------------------------- create
build_seed() {
  NAME=$1
  [ -f "$SSH_PUB" ] || die "public key not found: $SSH_PUB"
  capi=$(cat "$SSH_PUB")
  d="$WORK/$NAME"
  mkdir -p "$d"
  # unique instance-id so cloud-init runs fresh on every (re)create
  printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$NAME" "$(date +%s)" "$NAME" > "$d/meta-data"
  cat > "$d/user-data" <<EOF
#cloud-config
# Minimal handoff: root reachable over SSH with the deploy key. Networking via lab DHCP.
# Exception to "key-only": open-vm-tools is installed here because it is
# hypervisor-specific (ESXi needs the guest agent for IP reporting and graceful
# shutdown) and irrelevant on bare-VPS providers — so it is an ESXi-seed concern,
# not something the provider-agnostic ansible bootstrap should carry.
disable_root: false
ssh_pwauth: false
users:
  - default
  - name: root
    ssh_authorized_keys:
      - $capi
packages:
  - open-vm-tools
write_files:
  - path: /etc/ssh/sshd_config.d/00-vz-root.conf
    permissions: '0600'
    content: |
      PermitRootLogin prohibit-password
      PubkeyAuthentication yes
runcmd:
  - [ systemctl, enable, --now, vmtoolsd ]
  - [ systemctl, restart, sshd ]
EOF
  # Lint: a single bad escape silently voids the whole cloud-config — never ship unparsed.
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]).read())' "$d/user-data" \
      || die "user-data is not valid YAML"
  fi

  # Gateway: STATIC both NICs (NoCloud network-config v2). Workers omit this and
  # take DHCP. Each NIC is matched by its pinned MAC and renamed ext/int so the
  # gateway role's interface names are stable regardless of PCI enumeration.
  ncfg=""
  if [ "$GATEWAY" -eq 1 ]; then
    int_prefix=${INT_CIDR##*/}
    cat > "$d/network-config" <<EOF
version: 2
ethernets:
  ext:
    match:
      macaddress: "$OVH_MAC"
    set-name: ext
    addresses:
      - $PUB_ADDR/$PUB_PREFIX
    routes:
      - to: default
        via: $PUB_GW
    nameservers:
      addresses: [$PUB_DNS]
  int:
    match:
      macaddress: "$INT_MAC"
    set-name: int
    addresses:
      - $INT_ADDR/$int_prefix
EOF
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]).read())' "$d/network-config" \
        || die "network-config is not valid YAML"
    fi
    ncfg="$d/network-config"
  fi

  xorrisofs -quiet -output "$d/seed.iso" -volid CIDATA -joliet -rock \
    "$d/meta-data" "$d/user-data" ${ncfg:+"$ncfg"}
  scp -q "$d/seed.iso" "$ESXI:$DATASTORE/images/$NAME-seed.iso"
}

write_vmx() {
  NAME=$1
  # NIC section differs by role. Worker: one vmxnet3 on the Internal portgroup with a
  # generated MAC (the script reads it back to find the DHCP lease). Gateway: two
  # NICs — ext on the public portgroup pinned to the OVH virtual MAC (checkMACAddress
  # FALSE so ESXi accepts the non-VMware OUI), int on the Internal portgroup with a
  # pinned VMware-range MAC. The seed matches both by MAC and renames them ext/int.
  if [ "$GATEWAY" -eq 1 ]; then
    net=$(cat <<EOF
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.networkName = "$PUB_PORTGROUP"
ethernet0.addressType = "static"
ethernet0.address = "$OVH_MAC"
ethernet0.checkMACAddress = "FALSE"
ethernet1.present = "TRUE"
ethernet1.virtualDev = "vmxnet3"
ethernet1.networkName = "$PORTGROUP"
ethernet1.addressType = "static"
ethernet1.address = "$INT_MAC"
EOF
)
  else
    net=$(cat <<EOF
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.networkName = "$PORTGROUP"
ethernet0.addressType = "generated"
EOF
)
  fi
  # Mirrors a known-good ESXi-created template: EFI + Secure Boot, pvscsi, vmxnet3 on
  # the internal portgroup, SVGA present+autodetect (avoids the framebuffer panic a
  # minimal VMX hits), serial-to-file console for headless boot/cloud-init debugging.
  esxi "cat > $DATASTORE/$NAME/$NAME.vmx" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "$NAME"
guestOS = "rockylinux-64"
firmware = "efi"
uefi.secureBoot.enabled = "TRUE"
memSize = "$MEM"
numvcpus = "$CPUS"
nvram = "$NAME.nvram"
chipset.motherboardLayout = "acpi"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
floppy0.present = "FALSE"
svga.present = "TRUE"
svga.autodetect = "TRUE"
scsi0.present = "TRUE"
scsi0.virtualDev = "pvscsi"
scsi0:0.present = "TRUE"
scsi0:0.deviceType = "scsi-hardDisk"
scsi0:0.fileName = "$NAME.vmdk"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "$DATASTORE/images/$NAME-seed.iso"
sata0:0.startConnected = "TRUE"
$net
serial0.present = "TRUE"
serial0.fileType = "file"
serial0.fileName = "$DATASTORE/$NAME/console.log"
serial0.yieldOnMsrRead = "TRUE"
EOF
}

create_vm() {
  NAME=$1
  if [ "$GATEWAY" -eq 1 ]; then
    [ -n "$OVH_MAC" ] || die "gateway mode needs OVH_MAC (the OVH virtual MAC)"
    [ -n "$PUB_ADDR" ] || die "gateway mode needs PUB_ADDR (the gateway's public IP)"
    [ -n "$PUB_GW" ]   || die "gateway mode needs PUB_GW (the provider's default gateway)"
  fi
  esxi "test -f $BASE_VMDK" || die "golden image missing: $BASE_VMDK"
  if esxi "test -d $DATASTORE/$NAME"; then
    die "$DATASTORE/$NAME already exists — destroy it first: $0 -d $NAME"
  fi

  log "building cloud-init seed"
  build_seed "$NAME"

  log "cloning golden image -> $NAME.vmdk"
  esxi "mkdir -p $DATASTORE/$NAME && vmkfstools -i $BASE_VMDK -d thin $DATASTORE/$NAME/$NAME.vmdk" >/dev/null

  if [ -n "$DISK" ]; then
    log "growing root disk to $DISK (cloud-init growpart extends root on first boot)"
    esxi "vmkfstools -X $DISK $DATASTORE/$NAME/$NAME.vmdk" >/dev/null
  fi

  log "writing VMX"
  write_vmx "$NAME"

  log "registering + powering on"
  vmid=$(esxi "vim-cmd solo/registervm $DATASTORE/$NAME/$NAME.vmx")
  esxi "vim-cmd vmsvc/power.on $vmid" >/dev/null
  log "vmid=$vmid"

  # The gateway has a known static public IP (it serves DHCP, so it has no lease
  # to wait for). Workers get a generated MAC that ESXi writes into the VMX once
  # powered on; we read it back and wait for the gateway's dnsmasq to lease an IP.
  if [ "$GATEWAY" -eq 1 ]; then
    ip=$PUB_ADDR
    log "gateway mode: static public IP $ip (no DHCP lease to wait for)"
  else
    log "reading generated MAC"
    mac=""
    i=0
    while [ $i -lt 15 ]; do
      i=$((i+1))
      mac=$(esxi "grep -i ethernet0.generatedAddress\\ = $DATASTORE/$NAME/$NAME.vmx 2>/dev/null" \
              | sed 's/.*"\(.*\)".*/\1/' | tr 'A-Z' 'a-z' || true)
      [ -n "$mac" ] && break
      sleep 2
    done
    [ -n "$mac" ] || die "could not read generated MAC from VMX"
    log "MAC=$mac"

    log "waiting for DHCP lease"
    ip=""
    i=0
    while [ $i -lt 60 ]; do
      i=$((i+1))
      ip=$(awk -v m="$mac" 'tolower($2)==m{print $3}' "$LEASES" 2>/dev/null | tail -1 || true)
      [ -n "$ip" ] && break
      sleep 3
    done
    [ -n "$ip" ] || die "no DHCP lease for $mac after ~3min (check console: $DATASTORE/$NAME/console.log)"
    log "lease: $ip"
  fi

  log "waiting for root SSH"
  i=0
  while [ $i -lt 40 ]; do
    i=$((i+1))
    if ssh -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
         root@"$ip" 'true' 2>/dev/null; then
      log "VM $NAME ready: root@$ip"
      echo "$ip"            # <- machine-readable result on stdout
      return 0
    fi
    sleep 3
  done
  die "lease present ($ip) but root SSH not ready (check console: $DATASTORE/$NAME/console.log)"
}

# ---------------------------------------------------------------- main
DESTROY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--destroy) DESTROY=1; shift ;;
    -g|--gateway) GATEWAY=1; shift ;;
    -h|--help) echo "usage: $0 [-d] [-g] NAME" >&2; exit 1 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
NAME=${1:-}
[ -n "$NAME" ] || die "VM name required"
case "$NAME" in *[!a-zA-Z0-9_-]*) die "name must be [a-zA-Z0-9_-]";; esac

ensure_agent
if [ "$DESTROY" -eq 1 ]; then destroy_vm "$NAME"; else create_vm "$NAME"; fi
