#!/bin/sh
# setup-master-dhcp.sh — run DHCP on the master's Internal interface so VMs on the
# Internal vSwitch get networking automatically, the way a VPS provider hands it over.
# DHCP-only (DNS disabled); clients get a public resolver directly and route out via NAT.
# Run as root on the master (Alpine). Idempotent.
#
# Config: ./config.env overrides the defaults below
# (INT_IF, EXT_IF, DHCP_RANGE, DHCP_ROUTER, DHCP_DNS).
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -f "$SCRIPT_DIR/config.env" ] && . "$SCRIPT_DIR/config.env"

INT_IF=${INT_IF:-eth1}
EXT_IF=${EXT_IF:-eth0}
DHCP_RANGE=${DHCP_RANGE:-10.10.10.50,10.10.10.150,12h}
DHCP_ROUTER=${DHCP_ROUTER:-10.10.10.1}
DHCP_DNS=${DHCP_DNS:-8.8.8.8}

apk add --no-cache dnsmasq >/dev/null

cat > /etc/dnsmasq.d/internal.conf <<EOF
# Internal lab DHCP (master = NAT gateway $DHCP_ROUTER)
port=0
interface=$INT_IF
bind-interfaces
except-interface=$EXT_IF
dhcp-range=$DHCP_RANGE
dhcp-option=option:router,$DHCP_ROUTER
dhcp-option=option:dns-server,$DHCP_DNS
dhcp-authoritative
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
log-dhcp
EOF

grep -q 'conf-dir=/etc/dnsmasq.d' /etc/dnsmasq.conf 2>/dev/null \
  || echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf

rc-update add dnsmasq default 2>/dev/null || true
rc-service dnsmasq restart

echo "== status =="
rc-service dnsmasq status 2>&1 | head -3
echo "== listening sockets (expect :67 on $INT_IF, no :53) =="
ss -ulnp 2>/dev/null | grep -E ':67|:53' || netstat -ulnp 2>/dev/null | grep -E ':67|:53' || true
