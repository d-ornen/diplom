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

variable "k3s_version" {
  type = string
}
