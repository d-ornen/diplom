output "kubeconfig_local_path" {
  description = "Local kubeconfig path fetched from target host."
  value       = module.base.local_kubeconfig_path
}

output "generated_public_key" {
  description = "Generated public key if generate_ssh_key = true."
  value       = var.generate_ssh_key ? tls_private_key.provisioner[0].public_key_openssh : null
}
