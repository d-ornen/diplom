#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-with-metrics.sh [--metrics-dir <path>] [--latex-entry <file>]

Options:
  --metrics-dir <path>   Metrics export directory with index.json.
  --latex-entry <file>   Main TeX file relative to archive/, default: Dyplom.tex.
  -h, --help             Show this help.
EOF
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)"
ARCHIVE_DIR="${REPO_ROOT}/archive"
INGEST_SCRIPT="${SCRIPT_DIR}/ingest-metrics.py"

METRICS_DIR=""
LATEX_ENTRY="Dyplom.tex"

while [ "${#}" -gt 0 ]; do
  case "$1" in
    --metrics-dir)
      METRICS_DIR="$2"
      shift 2
      ;;
    --latex-entry)
      LATEX_ENTRY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -n "${METRICS_DIR}" ]; then
  python3 "${INGEST_SCRIPT}" --metrics-dir "${METRICS_DIR}" --output-dir "${ARCHIVE_DIR}/generated/metrics"
fi

cd "${ARCHIVE_DIR}"
if command -v latexmk >/dev/null 2>&1; then
  latexmk -pdf -interaction=nonstopmode -halt-on-error "${LATEX_ENTRY}"
else
  pdflatex -interaction=nonstopmode -halt-on-error "${LATEX_ENTRY}"
  pdflatex -interaction=nonstopmode -halt-on-error "${LATEX_ENTRY}"
fi
