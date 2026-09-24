#!/bin/sh
# genesis-bootstrap.sh — build a throwaway Alpine control host directly on
# ESXi, on the failover IP's virtual MAC. This is step 3 (part A) of the
# Genesis procedure in README.md: the one Linux host you can build with
# nothing but ESXi's own busybox shell, before any seeder/Ansible exists.
#
# Runs ON ESXi (paste, scp, or wget this file there and `sh` it) — not
# through Ansible, since at genesis time there is no control host yet to
# run Ansible from. Also reusable for disaster recovery: after an
# inventory-wipe, this is how you rebuild a control host to work from
# before re-registering the surviving VMs.
#
# Usage (set the required vars, then run):
#   DS=/vmfs/volumes/datastore1 OVH_MAC=<failover-IP-virtual-MAC> \
#     sh genesis-bootstrap.sh
#
# ALLOW_MAC_CONFLICT=true only when intentionally reusing a MAC already
# bound to another (powered-off) VM — e.g. handing an existing failover IP
# from a dying gateway to a fresh bootstrap host. Never run two VMs with
# the same MAC powered on at once.

set -eu

: "${DS:?set DS, e.g. /vmfs/volumes/datastore1}"
: "${OVH_MAC:?set OVH_MAC to the failover IP's virtual MAC (type vmware)}"
VM_NAME="${VM_NAME:-alpine-bootstrap}"
ALPINE_VERSION="${ALPINE_VERSION:-3.24.1}"
DISK_SIZE="${DISK_SIZE:-8G}"
MEM_MB="${MEM_MB:-2048}"
NUM_CPUS="${NUM_CPUS:-2}"
ALLOW_MAC_CONFLICT="${ALLOW_MAC_CONFLICT:-false}"

VMDIR="$DS/$VM_NAME"
ISO="$DS/iso/alpine-virt-$ALPINE_VERSION-x86_64.iso"

test -f "$ISO" || { echo "missing $ISO — fetch it first (see README genesis step)"; exit 1; }
test ! -d "$VMDIR" || { echo "refusing to clobber existing $VMDIR"; exit 1; }

MAC_CHECK_LINE=""
if [ "$ALLOW_MAC_CONFLICT" = "true" ]; then
  MAC_CHECK_LINE='ethernet0.checkMACAddress = "FALSE"'
fi

mkdir -p "$VMDIR"
vmkfstools -c "$DISK_SIZE" -d thin "$VMDIR/$VM_NAME.vmdk"

cat > "$VMDIR/$VM_NAME.vmx" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "$VM_NAME"
guestOS = "other-64"
firmware = "efi"
numvcpus = "$NUM_CPUS"
memSize = "$MEM_MB"
vmci0.present = "TRUE"
scsi0.present = "TRUE"
scsi0.virtualDev = "pvscsi"
scsi0.pciSlotNumber = "160"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$VM_NAME.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"
sata0.present = "TRUE"
sata0.pciSlotNumber = "32"
sata0:0.present = "TRUE"
sata0:0.fileName = "$ISO"
sata0:0.deviceType = "cdrom-image"
sata0:0.startConnected = "TRUE"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.pciSlotNumber = "192"
ethernet0.networkName = "VM Network"
ethernet0.addressType = "static"
ethernet0.address = "$OVH_MAC"
$MAC_CHECK_LINE
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

VMID=$(vim-cmd solo/registervm "$VMDIR/$VM_NAME.vmx")
echo "registered $VM_NAME as vmid $VMID"
vim-cmd vmsvc/power.on "$VMID"
