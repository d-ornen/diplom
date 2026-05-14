#!/usr/bin/env bash
set -euo pipefail

INSTALL_MULTUS="${INSTALL_MULTUS:-true}"

cat >/etc/sysctl.d/99-shadow-4g.conf <<'EOF'
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=33554432
net.core.wmem_max=33554432
EOF

modprobe br_netfilter || true
sysctl --system

iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 >/dev/null 2>&1 \
  || iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360

if [ "${INSTALL_MULTUS}" = "true" ]; then
  kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
fi

kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "Network layer completed"
