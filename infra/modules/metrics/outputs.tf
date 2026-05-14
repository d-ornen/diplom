output "metrics_namespace" {
  description = "Namespace used by the metrics layer."
  value       = var.metrics_namespace
}

output "metrics_export_root" {
  description = "Remote host path reserved for metrics artifacts."
  value       = var.metrics_export_root
}
