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

variable "mcc" {
  type    = string
  default = "001"
}

variable "mnc" {
  type    = string
  default = "01"
}

variable "platform_replicas" {
  type    = number
  default = 1
}
