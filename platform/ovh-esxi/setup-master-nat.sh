#!/bin/sh
# setup-master-nat.sh — make the master a NAT gateway for the Internal vSwitch.
# Run as root on the master (Alpine). Safe to run while connected via the public
# interface (only the internal interface and forwarding are touched). Idempotent.
#
# Config: ./config.env overrides the defaults below (INT_IF, EXT_IF, INT_ADDR, INT_CIDR).
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -f "$SCRIPT_DIR/config.env" ] && . "$SCRIPT_DIR/config.env"

INT_IF=${INT_IF:-eth1}
EXT_IF=${EXT_IF:-eth0}
INT_ADDR=${INT_ADDR:-10.10.10.1}
INT_CIDR=${INT_CIDR:-10.10.10.0/24}

echo "== install iptables =="
apk add --no-cache iptables >/dev/null

echo "== configure $INT_IF persistently =="
if ! grep -q "auto $INT_IF" /etc/network/interfaces; then
    cat >> /etc/network/interfaces <<EOF

auto $INT_IF
iface $INT_IF inet static
    address $INT_ADDR
    netmask 255.255.255.0
EOF
fi
ifdown $INT_IF 2>/dev/null || true
ifup $INT_IF

echo "== enable IPv4 forwarding persistently =="
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/00-nat.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "== NAT + forward rules (idempotent) =="
iptables -t nat -C POSTROUTING -s $INT_CIDR -o $EXT_IF -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s $INT_CIDR -o $EXT_IF -j MASQUERADE
iptables -C FORWARD -i $INT_IF -o $EXT_IF -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i $INT_IF -o $EXT_IF -j ACCEPT
iptables -C FORWARD -i $EXT_IF -o $INT_IF -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i $EXT_IF -o $INT_IF -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "== persist iptables + enable on boot =="
/etc/init.d/iptables save
rc-update add iptables default 2>/dev/null || true
rc-update add sysctl boot 2>/dev/null || true

echo ""
echo "== RESULT =="
ip addr show $INT_IF | grep -E 'inet |state'
echo "ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)"
iptables -t nat -S POSTROUTING
echo "Done."
