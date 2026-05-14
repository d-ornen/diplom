# AGENTS.md

## Cursor Cloud specific instructions

### Overview

This is a Terraform IaC repository for provisioning a 4G Shadow Deployment testbed. There is **no application source code** to build — the repository contains only Terraform configuration and shell provisioning scripts. All workloads use pre-built public container images.

### Tooling

- **OpenTofu v1.9.0** is installed as a drop-in replacement for Terraform (symlinked as `terraform`). It supports the cross-variable validation syntax used in this codebase. The official Terraform binary cannot be downloaded due to `releases.hashicorp.com` being blocked.
- Providers are served from a local filesystem mirror at `/opt/terraform-mirror` (configured via `/home/ubuntu/.terraformrc`). The `TF_CLI_CONFIG_FILE` environment variable is set in `~/.bashrc`.

### Running commands

- **Lint (formatting):** `terraform fmt -check -recursive` from the repo root.
- **Validate:** `cd infra/live/dev && terraform init && terraform validate` (or `infra/live/stage`).
- **Plan:** Requires `-var="debian_host=<IP>" -var="generate_ssh_key=true"` (or a `terraform.tfvars` file). No real target host exists in this environment, so `terraform apply` cannot run.
- Before running `terraform validate` or `terraform plan`, you must run `terraform init` in the environment directory. The init is cached in `.terraform/` and persists across commands.

### Gotchas

1. The committed `.terraform.lock.hcl` has `darwin_arm64` hashes. On this VM (linux_amd64), you must delete it and re-run `terraform init` to regenerate it from the local mirror. Do **not** commit the regenerated lockfile.
2. The committed `.terraform/providers/` directory contains darwin_arm64 binaries — ignore these; the local mirror at `/opt/terraform-mirror` provides linux_amd64 versions.
3. `terraform plan` for the full stack will error on `filesha256()` referencing `.generated-shared.sh` because that file is created by `local_file` during apply. This is a known code design limitation, not an environment issue.
4. Two environments exist: `infra/live/dev` and `infra/live/stage` (identical structure, different variable defaults).
