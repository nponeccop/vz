#!/bin/sh
# make-rocky-vm.sh — create (or destroy) a Rocky 9 VM on ESXi that satisfies the
# vz handoff contract: clean Rocky, root reachable over SSH with the deploy key,
# networking via the lab's DHCP (master = NAT/DHCP gateway on the Internal vSwitch).
#
# Usage:
#   make-rocky-vm.sh NAME            create VM NAME, print its IP when reachable
#   make-rocky-vm.sh -d NAME         destroy VM NAME (power off, unregister, delete)
#
# Configuration: ./config.env (gitignored) overrides the defaults below.
# See config.env.example. Key vars: ESXI, DATASTORE, PORTGROUP, BASE_VMDK, MEM, CPUS.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -f "$SCRIPT_DIR/config.env" ] && . "$SCRIPT_DIR/config.env"

ESXI=${ESXI:-root@esxi.example.net}
DATASTORE=${DATASTORE:-/vmfs/volumes/datastore1}
PORTGROUP=${PORTGROUP:-Internal}
BASE_VMDK=${BASE_VMDK:-$DATASTORE/images/Rocky-9-base.vmdk}
SSH_PUB=${SSH_PUB:-$SCRIPT_DIR/../../ansible/ssh.pub}
LEASES=${LEASES:-/var/lib/misc/dnsmasq.leases}
MEM=${MEM:-2048}
CPUS=${CPUS:-1}
WORK=${WORK:-${TMPDIR:-/tmp}/ovh-esxi-seeds}

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
disable_root: false
ssh_pwauth: false
users:
  - default
  - name: root
    ssh_authorized_keys:
      - $capi
write_files:
  - path: /etc/ssh/sshd_config.d/00-vz-root.conf
    permissions: '0600'
    content: |
      PermitRootLogin prohibit-password
      PubkeyAuthentication yes
runcmd:
  - [ systemctl, restart, sshd ]
EOF
  # Lint: a single bad escape silently voids the whole cloud-config — never ship unparsed.
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]).read())' "$d/user-data" \
      || die "user-data is not valid YAML"
  fi
  xorrisofs -quiet -output "$d/seed.iso" -volid CIDATA -joliet -rock \
    "$d/meta-data" "$d/user-data"
  scp -q "$d/seed.iso" "$ESXI:$DATASTORE/images/$NAME-seed.iso"
}

write_vmx() {
  NAME=$1
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
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.networkName = "$PORTGROUP"
ethernet0.addressType = "generated"
serial0.present = "TRUE"
serial0.fileType = "file"
serial0.fileName = "$DATASTORE/$NAME/console.log"
serial0.yieldOnMsrRead = "TRUE"
EOF
}

create_vm() {
  NAME=$1
  esxi "test -f $BASE_VMDK" || die "golden image missing: $BASE_VMDK"
  if esxi "test -d $DATASTORE/$NAME"; then
    die "$DATASTORE/$NAME already exists — destroy it first: $0 -d $NAME"
  fi

  log "building cloud-init seed"
  build_seed "$NAME"

  log "cloning golden image -> $NAME.vmdk"
  esxi "mkdir -p $DATASTORE/$NAME && vmkfstools -i $BASE_VMDK -d thin $DATASTORE/$NAME/$NAME.vmdk" >/dev/null

  log "writing VMX"
  write_vmx "$NAME"

  log "registering + powering on"
  vmid=$(esxi "vim-cmd solo/registervm $DATASTORE/$NAME/$NAME.vmx")
  esxi "vim-cmd vmsvc/power.on $vmid" >/dev/null
  log "vmid=$vmid"

  # ESXi writes the generated MAC into the VMX once powered on
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
case "${1:-}" in
  -d|--destroy) DESTROY=1; shift ;;
  -h|--help|"") echo "usage: $0 [-d] NAME" >&2; exit 1 ;;
esac
NAME=${1:-}
[ -n "$NAME" ] || die "VM name required"
case "$NAME" in *[!a-zA-Z0-9_-]*) die "name must be [a-zA-Z0-9_-]";; esac

ensure_agent
if [ "$DESTROY" -eq 1 ]; then destroy_vm "$NAME"; else create_vm "$NAME"; fi
