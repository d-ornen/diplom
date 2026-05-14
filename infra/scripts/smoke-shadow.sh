#!/usr/bin/env bash
set -euo pipefail

if [ "${#}" -lt 3 ]; then
  echo "Usage: $0 <ssh_user> <host> <ssh_key_path> [ssh_port]" >&2
  exit 1
fi

SSH_USER="$1"
HOST="$2"
KEY_PATH="$3"
SSH_PORT="${4:-22}"

SSH_OPTS=(-o StrictHostKeyChecking=no -p "$SSH_PORT" -i "$KEY_PATH")

echo "[1/3] Checking app deployments"
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" \
  "kubectl -n shadow-apps get deploy api-prod api-shadow diff-analyzer"

echo "[2/3] Checking VirtualService and DestinationRule"
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" \
  "kubectl -n shadow-apps get virtualservice api-shadow-vs && kubectl -n shadow-apps get destinationrule api-dr"

echo "[3/3] Sending in-cluster probe traffic"
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" \
  "kubectl -n shadow-apps run curl-smoke --image=curlimages/curl:8.7.1 --rm -i --restart=Never --command -- sh -c 'curl -sS http://api.shadow-apps.svc.cluster.local'"

echo "Smoke checks completed"
