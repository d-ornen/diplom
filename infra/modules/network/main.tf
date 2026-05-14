resource "null_resource" "network_tuning" {
  triggers = {
    host           = var.host
    install_multus = tostring(var.install_multus)
    script_sha     = filesha256("${path.module}/../../scripts/provision/network.sh")
  }

  connection {
    type        = "ssh"
    host        = var.host
    port        = var.ssh_port
    user        = var.ssh_user
    private_key = var.ssh_private_key
    timeout     = "5m"
  }

  provisioner "file" {
    source      = "${path.module}/../../scripts/provision/network.sh"
    destination = "/tmp/shadow-network.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/shadow-network.sh",
      "sudo INSTALL_MULTUS='${var.install_multus}' /tmp/shadow-network.sh"
    ]
  }
}
