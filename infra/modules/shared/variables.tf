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

variable "istio_version" {
  type = string
}

variable "kube_prom_stack_version" {
  type = string
}

variable "apps_namespace" {
  type = string
}

variable "open5gs_namespace" {
  type = string
}
