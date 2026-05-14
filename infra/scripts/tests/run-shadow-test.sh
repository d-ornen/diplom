#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-shadow-test.sh --host <host> --ssh-user <user> --ssh-key <key_path> [options]

Options:
  --host <host>               Remote host with kubectl access.
  --ssh-user <user>           SSH username.
  --ssh-key <path>            SSH private key path.
  --ssh-port <port>           SSH port, default: 22.
  --scenario <name>           Scenario name, default: shadow-run.
  --namespace <name>          App namespace, default: shadow-apps.
  --duration <duration>       Load test duration, default: 2m.
  --vus <count>               Virtual users for k6, default: 10.
  --rps <count>               Optional request-per-second cap for k6.
  --request-count <count>     Fixed iteration count mode for k6/curl fallback.
  --mirror <on|off>           Toggle shadow mirroring before test.
  --mirror-percentage <0-100> Mirrored traffic percentage, default: 100.
  --mcc <code>                Optional MCC marker for logs.
  --mnc <code>                Optional MNC marker for logs.
  --out-dir <path>            Parent directory for artifacts, default: current directory.
  --collect-step <duration>   Metrics collection step, default: 15s.

Examples:
  run-shadow-test.sh --host 203.0.113.10 --ssh-user debian --ssh-key ~/.ssh/id_ed25519 \
    --scenario baseline --duration 3m --vus 20 --mirror on --mirror-percentage 30
EOF
}

HOST="${HOST:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"
SCENARIO="${SCENARIO:-shadow-run}"
NAMESPACE="${NAMESPACE:-shadow-apps}"
DURATION="${DURATION:-2m}"
VUS="${VUS:-10}"
RPS="${RPS:-}"
REQUEST_COUNT="${REQUEST_COUNT:-0}"
MIRROR_TOGGLE="${MIRROR_TOGGLE:-on}"
MIRROR_PERCENTAGE="${MIRROR_PERCENTAGE:-100}"
MCC="${MCC:-}"
MNC="${MNC:-}"
OUT_DIR="${OUT_DIR:-.}"
COLLECT_STEP="${COLLECT_STEP:-15s}"

while [ "${#}" -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --scenario) SCENARIO="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --vus) VUS="$2"; shift 2 ;;
    --rps) RPS="$2"; shift 2 ;;
    --request-count) REQUEST_COUNT="$2"; shift 2 ;;
    --mirror) MIRROR_TOGGLE="$2"; shift 2 ;;
    --mirror-percentage) MIRROR_PERCENTAGE="$2"; shift 2 ;;
    --mcc) MCC="$2"; shift 2 ;;
    --mnc) MNC="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --collect-step) COLLECT_STEP="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${HOST}" ] || [ -z "${SSH_USER}" ] || [ -z "${SSH_KEY}" ]; then
  echo "Error: --host, --ssh-user and --ssh-key are required." >&2
  usage >&2
  exit 1
fi

if [ ! -f "${SSH_KEY}" ]; then
  echo "Error: SSH key not found: ${SSH_KEY}" >&2
  exit 1
fi

case "${MIRROR_TOGGLE}" in
  on|off) ;;
  *)
    echo "Error: --mirror must be on or off." >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COLLECT_SCRIPT="${SCRIPT_DIR}/../metrics/collect-metrics.sh"

if [ ! -x "${COLLECT_SCRIPT}" ]; then
  echo "Error: collector script is not executable: ${COLLECT_SCRIPT}" >&2
  exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -p ${SSH_PORT} -i ${SSH_KEY}"
API_HOST="api.${NAMESPACE}.svc.cluster.local"
RUN_STAMP="$(date +"%Y%m%d_%H%M%S")"
SCENARIO_SAFE="$(printf '%s' "${SCENARIO}" | tr ' ' '_' | tr -cd 'A-Za-z0-9_.-')"
ARTIFACT_DIR="${OUT_DIR}/test-runs/${RUN_STAMP}_${SCENARIO_SAFE}"
mkdir -p "${ARTIFACT_DIR}"

echo "Preparing mirror routing (${MIRROR_TOGGLE}, ${MIRROR_PERCENTAGE}%)"
if [ "${MIRROR_TOGGLE}" = "on" ]; then
  ssh ${SSH_OPTS} "${SSH_USER}@${HOST}" \
    "kubectl -n '${NAMESPACE}' patch virtualservice api-shadow-vs --type merge -p \
      '{\"spec\":{\"http\":[{\"route\":[{\"destination\":{\"host\":\"${API_HOST}\",\"subset\":\"v1\"},\"weight\":100}],\"mirror\":{\"host\":\"${API_HOST}\",\"subset\":\"v2\"},\"mirrorPercentage\":{\"value\":${MIRROR_PERCENTAGE}}}]}}'"
else
  ssh ${SSH_OPTS} "${SSH_USER}@${HOST}" \
    "kubectl -n '${NAMESPACE}' patch virtualservice api-shadow-vs --type merge -p \
      '{\"spec\":{\"http\":[{\"route\":[{\"destination\":{\"host\":\"${API_HOST}\",\"subset\":\"v1\"},\"weight\":100}]}]}}'"
fi

START_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Load phase started at ${START_TS}" | tee "${ARTIFACT_DIR}/run.log"

K6_SCRIPT="$(mktemp)"
trap 'rm -f "${K6_SCRIPT}"' EXIT
cat >"${K6_SCRIPT}" <<'EOF'
import http from "k6/http";
import { sleep } from "k6";

export default function () {
  http.get(__ENV.TARGET_URL);
  sleep(1);
}
EOF

LOAD_STATUS="k6_success"
K6_CMD="k6 run --insecure-skip-tls-verify --vus ${VUS} --duration ${DURATION}"
if [ "${REQUEST_COUNT}" -gt 0 ] 2>/dev/null; then
  K6_CMD="k6 run --insecure-skip-tls-verify --vus ${VUS} --iterations ${REQUEST_COUNT}"
elif [ -n "${RPS}" ]; then
  K6_CMD="${K6_CMD} --rps ${RPS}"
fi

if ! ssh ${SSH_OPTS} "${SSH_USER}@${HOST}" \
  "kubectl -n '${NAMESPACE}' run shadow-k6-runner --image=grafana/k6:latest --rm -i --restart=Never --command -- sh -lc 'TARGET_URL=http://${API_HOST} ${K6_CMD} -'" \
  <"${K6_SCRIPT}" | tee -a "${ARTIFACT_DIR}/run.log"; then
  LOAD_STATUS="k6_failed_curl_fallback"
  echo "k6 failed, falling back to curl loop." | tee -a "${ARTIFACT_DIR}/run.log"

  ssh ${SSH_OPTS} "${SSH_USER}@${HOST}" \
    "REQUEST_COUNT='${REQUEST_COUNT}' DURATION='${DURATION}' URL='http://${API_HOST}' sh -lc '
      set -eu
      req_total=0
      if [ \"\$REQUEST_COUNT\" -gt 0 ] 2>/dev/null; then
        limit=\"\$REQUEST_COUNT\"
      else
        limit=300
      fi
      i=0
      while [ \"\$i\" -lt \"\$limit\" ]; do
        curl -fsS \"\$URL\" >/dev/null || true
        i=\$((i + 1))
      done
      echo \"curl_requests_sent=\$i\"
    '" | tee -a "${ARTIFACT_DIR}/run.log"
fi

END_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Load phase ended at ${END_TS}" | tee -a "${ARTIFACT_DIR}/run.log"

cat >"${ARTIFACT_DIR}/run-context.json" <<EOF
{
  "scenario": "${SCENARIO}",
  "namespace": "${NAMESPACE}",
  "host": "${HOST}",
  "start": "${START_TS}",
  "end": "${END_TS}",
  "duration": "${DURATION}",
  "vus": ${VUS},
  "rps": "${RPS}",
  "request_count": ${REQUEST_COUNT},
  "mirror": "${MIRROR_TOGGLE}",
  "mirror_percentage": ${MIRROR_PERCENTAGE},
  "mcc": "${MCC}",
  "mnc": "${MNC}",
  "load_status": "${LOAD_STATUS}"
}
EOF

"${COLLECT_SCRIPT}" \
  --host "${HOST}" \
  --ssh-user "${SSH_USER}" \
  --ssh-key "${SSH_KEY}" \
  --ssh-port "${SSH_PORT}" \
  --scenario "${SCENARIO}" \
  --start "${START_TS}" \
  --end "${END_TS}" \
  --step "${COLLECT_STEP}" \
  --out-dir "${ARTIFACT_DIR}" | tee -a "${ARTIFACT_DIR}/run.log"

echo "Artifacts written to: ${ARTIFACT_DIR}"
