# stage environment

This environment composes all layers for a single Debian host.

## Non-interactive usage

1. Copy vars:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Set host and SSH access in `terraform.tfvars`.

3. Optional: pass sensitive values via env vars:

```bash
export TF_VAR_ssh_private_key_pem="$(cat ~/.ssh/id_rsa)"
```

4. Run:

```bash
terraform init
terraform apply -auto-approve
```

## Toggle shadow mirroring

- Enabled:
  - `enable_shadow_mirroring = true`
- Disabled:
  - `enable_shadow_mirroring = false`
- Control mirrored traffic share:
  - `mirror_percentage = 0..100`

## Experiment knobs

- Telecom identity: `mcc`, `mnc`
- Telecom platform scaling: `platform_replicas`
- API workload scaling: `app_prod_replicas`, `app_shadow_replicas`

Re-run `terraform apply -auto-approve` after changing the toggle.
