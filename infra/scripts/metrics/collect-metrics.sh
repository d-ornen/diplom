#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: collect-metrics.sh --host <host> --ssh-user <user> --ssh-key <key_path> [options]

Options:
  --host <host>            Remote host with kubectl access (or HOST env).
  --ssh-user <user>        SSH user (or SSH_USER env).
  --ssh-key <path>         SSH private key path (or SSH_KEY env).
  --ssh-port <port>        SSH port, default: 22 (or SSH_PORT env).
  --scenario <name>        Scenario label, default: adhoc (or SCENARIO env).
  --start <rfc3339>        Query window start timestamp (UTC).
  --end <rfc3339>          Query window end timestamp (UTC).
  --step <duration>        Prometheus query step, default: 15s.
  --out-dir <path>         Parent output directory, default: current directory.
  --queries-file <path>    KPI query file, default: script local promql-queries.json.

If --start/--end are not provided, script uses [now-10m, now].
Exports:
  <out-dir>/metrics-exports/YYYYMMDD_HHMMSS_<scenario>/
EOF
}

HOST="${HOST:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"
SCENARIO="${SCENARIO:-adhoc}"
START_TS="${START:-}"
END_TS="${END:-}"
STEP="${STEP:-15s}"
OUT_DIR="${OUT_DIR:-.}"
PROM_NAMESPACE="${PROM_NAMESPACE:-monitoring}"
PROM_API_PATH="${PROM_API_PATH:-/api/v1/query_range}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
QUERIES_FILE="${QUERIES_FILE:-${SCRIPT_DIR}/promql-queries.json}"

while [ "${#}" -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --scenario) SCENARIO="$2"; shift 2 ;;
    --start) START_TS="$2"; shift 2 ;;
    --end) END_TS="$2"; shift 2 ;;
    --step) STEP="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --queries-file) QUERIES_FILE="$2"; shift 2 ;;
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

if [ ! -f "${QUERIES_FILE}" ]; then
  echo "Error: queries file not found: ${QUERIES_FILE}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

if [ -z "${END_TS}" ]; then
  END_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

if [ -z "${START_TS}" ]; then
  START_TS="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
fi

RUN_STAMP="$(date +"%Y%m%d_%H%M%S")"
SCENARIO_SAFE="$(printf '%s' "${SCENARIO}" | tr ' ' '_' | tr -cd 'A-Za-z0-9_.-')"
if [ -z "${SCENARIO_SAFE}" ]; then
  SCENARIO_SAFE="adhoc"
fi

RUN_DIR="${OUT_DIR}/metrics-exports/${RUN_STAMP}_${SCENARIO_SAFE}"
mkdir -p "${RUN_DIR}"

SSH_OPTS="-o StrictHostKeyChecking=no -p ${SSH_PORT} -i ${SSH_KEY}"

PROM_ENDPOINT="$(ssh ${SSH_OPTS} "${SSH_USER}@${HOST}" "sh -lc '
set -eu
ns=\"${PROM_NAMESPACE}\"
svc=\$(kubectl -n \"\$ns\" get svc -l app.kubernetes.io/name=prometheus -o jsonpath=\"{.items[0].metadata.name}\" 2>/dev/null || true)
if [ -z \"\$svc\" ]; then
  svc=\"kube-prometheus-stack-prometheus\"
fi
printf \"http://%s.%s.svc.cluster.local:9090\" \"\$svc\" \"\$ns\"
'")"

if [ -z "${PROM_ENDPOINT}" ]; then
  echo "Error: failed to resolve Prometheus endpoint." >&2
  exit 1
fi

EXPORTS_META_FILE="$(mktemp)"
MISSING_META_FILE="$(mktemp)"
trap 'rm -f "${EXPORTS_META_FILE}" "${MISSING_META_FILE}"' EXIT

printf "Collecting metrics from %s to %s (step=%s)\n" "${START_TS}" "${END_TS}" "${STEP}"

jq -c '.queries[]' "${QUERIES_FILE}" | while IFS= read -r item; do
  name="$(printf '%s' "${item}" | jq -r '.name')"
  query="$(printf '%s' "${item}" | jq -r '.query')"
  query_file_safe="$(printf '%s' "${name}" | tr ' ' '_' | tr -cd 'A-Za-z0-9_.-')"
  raw_file="${RUN_DIR}/${query_file_safe}.raw.json"
  csv_file="${RUN_DIR}/${query_file_safe}.csv"

  query_b64="$(printf '%s' "${query}" | base64 | tr -d '\n')"

  if ! ssh ${SSH_OPTS} "${SSH_USER}@${HOST}" \
    "PROM_ENDPOINT='${PROM_ENDPOINT}' START_TS='${START_TS}' END_TS='${END_TS}' STEP='${STEP}' QUERY_B64='${query_b64}' sh -lc '
      set -eu
      query=\$(printf \"%s\" \"\$QUERY_B64\" | base64 -d)
      curl -sS --get \
        --data-urlencode \"query=\$query\" \
        --data-urlencode \"start=\$START_TS\" \
        --data-urlencode \"end=\$END_TS\" \
        --data-urlencode \"step=\$STEP\" \
        \"\$PROM_ENDPOINT${PROM_API_PATH}\"
    '" >"${raw_file}"; then
    echo "WARN: query failed: ${name}" >&2
    printf '{"name":"%s","reason":"remote_query_failed"}\n' "${name}" >>"${MISSING_META_FILE}"
    printf 'series,timestamp,value,labels_json\n' >"${csv_file}"
    printf '{"name":"%s","raw":"%s","csv":"%s","series":0,"status":"failed"}\n' \
      "${name}" "${raw_file}" "${csv_file}" >>"${EXPORTS_META_FILE}"
    continue
  fi

  status="$(jq -r '.status // "unknown"' "${raw_file}" 2>/dev/null || printf 'invalid_json')"
  if [ "${status}" != "success" ]; then
    echo "WARN: non-success response for query: ${name}" >&2
    printf '{"name":"%s","reason":"status_%s"}\n' "${name}" "${status}" >>"${MISSING_META_FILE}"
  fi

  series_count="$(jq -r '.data.result | length // 0' "${raw_file}" 2>/dev/null || printf '0')"
  if [ "${series_count}" = "0" ]; then
    printf '{"name":"%s","reason":"no_series"}\n' "${name}" >>"${MISSING_META_FILE}"
  fi

  {
    printf 'series,timestamp,value,labels_json\n'
    jq -r '
      if .status != "success" or (.data.result | type != "array") then
        empty
      else
        .data.result
        | to_entries[]
        | .key as $series
        | .value.metric as $metric
        | ($metric | tojson) as $labels
        | .value.values[]
        | [$series, .[0], .[1], $labels] | @csv
      end
    ' "${raw_file}"
  } >"${csv_file}"

  printf '{"name":"%s","raw":"%s","csv":"%s","series":%s,"status":"%s"}\n' \
    "${name}" "${raw_file}" "${csv_file}" "${series_count}" "${status}" >>"${EXPORTS_META_FILE}"
done

EXPORTS_JSON="$(jq -s '.' "${EXPORTS_META_FILE}")"
MISSING_JSON="$(jq -s '.' "${MISSING_META_FILE}")"

INDEX_FILE="${RUN_DIR}/index.json"
jq -n \
  --arg timestamp "${RUN_STAMP}" \
  --arg scenario "${SCENARIO}" \
  --arg host "${HOST}" \
  --arg ssh_user "${SSH_USER}" \
  --argjson ssh_port "${SSH_PORT}" \
  --arg start "${START_TS}" \
  --arg end "${END_TS}" \
  --arg step "${STEP}" \
  --arg out_dir "${RUN_DIR}" \
  --arg queries_file "${QUERIES_FILE}" \
  --arg prometheus_endpoint "${PROM_ENDPOINT}" \
  --argjson exports "${EXPORTS_JSON}" \
  --argjson missing_queries "${MISSING_JSON}" \
  '{
    timestamp: $timestamp,
    scenario: $scenario,
    parameters: {
      host: $host,
      ssh_user: $ssh_user,
      ssh_port: $ssh_port,
      start: $start,
      end: $end,
      step: $step,
      queries_file: $queries_file,
      prometheus_endpoint: $prometheus_endpoint
    },
    out_dir: $out_dir,
    exports: $exports,
    missing_queries: $missing_queries
  }' >"${INDEX_FILE}"

echo "Metrics export completed: ${RUN_DIR}"
echo "Index file: ${INDEX_FILE}"
