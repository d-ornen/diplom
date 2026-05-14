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
- `scripts/provision`: host-side scripts executed through Terraform provisioners.
