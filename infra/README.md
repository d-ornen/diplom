# 4G Shadow Deployment IaC

This directory contains Terraform code to bootstrap a single-node Debian testbed
for 4G shadow deployment research.

## Layers

- `live/dev`: composition root and environment variables.
- `modules/base`: host bootstrap (SSH, Docker, K3s).
- `modules/network`: node networking, MTU/MSS, Multus.
- `modules/shared`: shared cluster stack (Istio, observability, namespaces).
- `modules/platform-apps`: data and telecom platform apps (MongoDB, Open5GS, UERANSIM, k6).
- `modules/apps`: workload apps (prod/shadow) and shadow routing policies.
- `modules/metrics`: read-oriented metrics layer (RBAC + export path bootstrap).
- `scripts/provision`: host-side scripts executed through Terraform provisioners.

## Metrics + Shadow Test automation

- KPI query definitions: `scripts/metrics/promql-queries.json`.
- Metrics collector: `scripts/metrics/collect-metrics.sh`.
- Automated scenario runner: `scripts/tests/run-shadow-test.sh`.
- Exports are stored under `metrics-exports/YYYYMMDD_HHMMSS_<scenario>/` with `index.json` plus per-query raw JSON and CSV.

Example:

```bash
infra/scripts/tests/run-shadow-test.sh \
  --host 203.0.113.10 \
  --ssh-user debian \
  --ssh-key ~/.ssh/id_ed25519 \
  --scenario stage-baseline \
  --namespace shadow-apps \
  --duration 3m \
  --vus 20 \
  --mirror on \
  --mirror-percentage 30
```
