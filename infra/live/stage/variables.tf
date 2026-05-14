variable "environment" {
  description = "Environment name."
  type        = string
  default     = "stage"
}

variable "debian_host" {
  description = "Debian server IP or DNS."
  type        = string
}

variable "ssh_user" {
  description = "SSH username for provisioning."
  type        = string
  default     = "debian"
}

variable "ssh_port" {
  description = "SSH port."
  type        = number
  default     = 22
}

variable "ssh_private_key_path" {
  description = "Path to existing private key. Used when generate_ssh_key = false."
  type        = string
  default     = ""
}

variable "ssh_private_key_pem" {
  description = "Inline private key PEM. Takes precedence over path if set."
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition = (
      var.generate_ssh_key ||
      length(trimspace(var.ssh_private_key_pem)) > 0 ||
      length(trimspace(var.ssh_private_key_path)) > 0
    )
    error_message = "Set generate_ssh_key=true or provide ssh_private_key_pem/ssh_private_key_path."
  }
}

variable "generate_ssh_key" {
  description = "Generate SSH keypair with Terraform."
  type        = bool
  default     = false
}

variable "generated_private_key_output_path" {
  description = "Where to save generated private key locally."
  type        = string
  default     = ".generated/stage-shadow-key.pem"
}

variable "k3s_version" {
  description = "K3s install version."
  type        = string
  default     = "v1.30.2+k3s2"
}

variable "install_multus" {
  description = "Install Multus CNI in network layer."
  type        = bool
  default     = true
}

variable "istio_version" {
  description = "Istio chart version."
  type        = string
  default     = "1.22.2"
}

variable "kube_prom_stack_version" {
  description = "kube-prometheus-stack chart version."
  type        = string
  default     = "58.5.1"
}

variable "apps_namespace" {
  description = "Namespace for user workloads."
  type        = string
  default     = "shadow-apps"
}

variable "open5gs_namespace" {
  description = "Namespace for Open5GS and UERANSIM."
  type        = string
  default     = "telecom"
}

variable "mcc" {
  description = "Mobile Country Code for telecom simulation."
  type        = string
  default     = "001"
}

variable "mnc" {
  description = "Mobile Network Code for telecom simulation."
  type        = string
  default     = "01"
}

variable "platform_replicas" {
  description = "Replica count for telecom platform deployments."
  type        = number
  default     = 1
}

variable "app_prod_replicas" {
  description = "Replica count for production API deployment."
  type        = number
  default     = 1
}

variable "app_shadow_replicas" {
  description = "Replica count for shadow API deployment."
  type        = number
  default     = 1
}

variable "enable_shadow_mirroring" {
  description = "Enable Istio shadow mirroring route."
  type        = bool
  default     = true
}

variable "mirror_percentage" {
  description = "Percentage of traffic mirrored to shadow deployment."
  type        = number
  default     = 100

  validation {
    condition     = var.mirror_percentage >= 0 && var.mirror_percentage <= 100
    error_message = "mirror_percentage must be between 0 and 100."
  }
}
