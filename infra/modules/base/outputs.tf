output "local_kubeconfig_path" {
  value = "${path.root}/.kubeconfig-${var.host}"
}
