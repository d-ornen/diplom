locals {
  provided_inline_key = trimspace(var.ssh_private_key_pem)
  provided_path_key   = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : ""
  generated_key       = var.generate_ssh_key ? tls_private_key.provisioner[0].private_key_pem : ""

  ssh_private_key = coalesce(
    length(local.provided_inline_key) > 0 ? local.provided_inline_key : null,
    length(local.generated_key) > 0 ? local.generated_key : null,
    length(local.provided_path_key) > 0 ? local.provided_path_key : null,
    ""
  )
}

resource "tls_private_key" "provisioner" {
  count     = var.generate_ssh_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "generated_private_key" {
  count           = var.generate_ssh_key ? 1 : 0
  filename        = var.generated_private_key_output_path
  content         = tls_private_key.provisioner[0].private_key_pem
  file_permission = "0600"
}

module "base" {
  source = "../../modules/base"

  host            = var.debian_host
  ssh_user        = var.ssh_user
  ssh_port        = var.ssh_port
  ssh_private_key = local.ssh_private_key
  k3s_version     = var.k3s_version
}

module "network" {
  source = "../../modules/network"

  host            = var.debian_host
  ssh_user        = var.ssh_user
  ssh_port        = var.ssh_port
  ssh_private_key = local.ssh_private_key
  install_multus  = var.install_multus

  depends_on = [module.base]
}

module "shared" {
  source = "../../modules/shared"

  host                     = var.debian_host
  ssh_user                 = var.ssh_user
  ssh_port                 = var.ssh_port
  ssh_private_key          = local.ssh_private_key
  istio_version            = var.istio_version
  kube_prom_stack_version  = var.kube_prom_stack_version
  apps_namespace           = var.apps_namespace
  open5gs_namespace        = var.open5gs_namespace

  depends_on = [module.network]
}

module "platform_apps" {
  source = "../../modules/platform-apps"

  host            = var.debian_host
  ssh_user        = var.ssh_user
  ssh_port        = var.ssh_port
  ssh_private_key = local.ssh_private_key
  namespace       = var.open5gs_namespace
  mcc             = var.mcc
  mnc             = var.mnc
  platform_replicas = var.platform_replicas

  depends_on = [module.shared]
}

module "apps" {
  source = "../../modules/apps"

  host                    = var.debian_host
  ssh_user                = var.ssh_user
  ssh_port                = var.ssh_port
  ssh_private_key         = local.ssh_private_key
  namespace               = var.apps_namespace
  enable_shadow_mirroring = var.enable_shadow_mirroring
  app_prod_replicas       = var.app_prod_replicas
  app_shadow_replicas     = var.app_shadow_replicas
  mirror_percentage       = var.mirror_percentage

  depends_on = [module.platform_apps]
}

provider "kubernetes" {
  config_path = module.base.local_kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = module.base.local_kubeconfig_path
  }
}
