# Metrics to LaTeX pipeline

This repository now supports a local pipeline that converts exported metrics into LaTeX-ready tables and charts.

## Prerequisites

- `python3`
- LaTeX toolchain:
  - preferred: `latexmk`
  - fallback: `pdflatex`
- `pgfplots` LaTeX package for chart rendering (without it, document still compiles and shows a note)

## Build with real metrics

```bash
archive/tools/build-with-metrics.sh --metrics-dir artifacts/metrics-exports/YYYYMMDD_HHMMSS_scenario
```

## Build without metrics refresh

```bash
archive/tools/build-with-metrics.sh
```

## Direct ingestion only

```bash
python3 archive/tools/ingest-metrics.py \
  --metrics-dir artifacts/metrics-exports/YYYYMMDD_HHMMSS_scenario \
  --output-dir archive/generated/metrics
```

## Generated outputs

Metrics ingestion writes files to `archive/generated/metrics/`:

- `scenario.tex` metadata include
- `request_rate.tsv`
- `latency_p95_p99.tsv`
- `error_rate.tsv`
- `prod_shadow_counts.tsv`
- optional `pod_cpu_usage.tsv`
- optional `pod_memory_usage.tsv`

Missing source query files are tolerated; unavailable charts are skipped automatically.
