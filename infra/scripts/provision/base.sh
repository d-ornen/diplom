#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
K3S_VERSION="${K3S_VERSION:-v1.30.2+k3s2}"

apt-get update
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  software-properties-common \
  jq

if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable docker
systemctl restart docker

if ! systemctl is-active --quiet k3s; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -
fi

systemctl enable k3s
systemctl restart k3s

until kubectl get nodes >/dev/null 2>&1; do
  sleep 2
done

mkdir -p /home/${SUDO_USER:-$USER}/.kube || true
cp /etc/rancher/k3s/k3s.yaml /home/${SUDO_USER:-$USER}/.kube/config || true
chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} /home/${SUDO_USER:-$USER}/.kube || true

echo "Base layer completed"
