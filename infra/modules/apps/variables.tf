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

variable "namespace" {
  type = string
}

variable "enable_shadow_mirroring" {
  type = bool
}

variable "app_prod_replicas" {
  type    = number
  default = 1
}

variable "app_shadow_replicas" {
  type    = number
  default = 1
}

variable "mirror_percentage" {
  type    = number
  default = 100

  validation {
    condition     = var.mirror_percentage >= 0 && var.mirror_percentage <= 100
    error_message = "mirror_percentage must be between 0 and 100."
  }
}
