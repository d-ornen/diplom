resource "local_sensitive_file" "ssh_key_for_scp" {
  filename        = "${path.root}/.terraform-shadow-key.pem"
  content         = var.ssh_private_key
  file_permission = "0600"
}

resource "null_resource" "bootstrap_host" {
  triggers = {
    host        = var.host
    ssh_user    = var.ssh_user
    ssh_port    = tostring(var.ssh_port)
    k3s_version = var.k3s_version
    script_sha  = filesha256("${path.module}/../../scripts/provision/base.sh")
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
    source      = "${path.module}/../../scripts/provision/base.sh"
    destination = "/tmp/shadow-base.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/shadow-base.sh",
      "sudo K3S_VERSION='${var.k3s_version}' /tmp/shadow-base.sh"
    ]
  }

  depends_on = [local_sensitive_file.ssh_key_for_scp]
}

resource "null_resource" "fetch_kubeconfig" {
  triggers = {
    host         = var.host
    ssh_user     = var.ssh_user
    ssh_port     = tostring(var.ssh_port)
    bootstrap_id = null_resource.bootstrap_host.id
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -P ${var.ssh_port} -i ${local_sensitive_file.ssh_key_for_scp.filename} ${var.ssh_user}@${var.host}:/etc/rancher/k3s/k3s.yaml ${path.root}/.kubeconfig-${var.host}"
  }

  provisioner "local-exec" {
    command = "perl -0pi -e 's|https://127.0.0.1:6443|https://${var.host}:6443|g' ${path.root}/.kubeconfig-${var.host}"
  }

  depends_on = [null_resource.bootstrap_host]
}
