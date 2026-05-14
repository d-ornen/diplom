variable "host" {
  type = string
}

variable "ssh_user" {
  type = string
}

variable "ssh_port" {
  type = number
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "metrics_namespace" {
  description = "Namespace where metrics collectors/readers are defined."
  type        = string
}

variable "metrics_export_root" {
  description = "Default directory on host reserved for metrics export artifacts."
  type        = string
}
