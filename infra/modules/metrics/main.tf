resource "local_file" "metrics_manifest" {
  filename = "${path.module}/.generated-metrics-layer.yaml"
  content  = <<-EOT
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: metrics-reader
      namespace: ${var.metrics_namespace}
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: metrics-reader
    rules:
      - apiGroups: [""]
        resources: ["pods", "services", "endpoints", "namespaces"]
        verbs: ["get", "list", "watch"]
      - nonResourceURLs: ["/metrics"]
        verbs: ["get"]
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: metrics-reader
    subjects:
      - kind: ServiceAccount
        name: metrics-reader
        namespace: ${var.metrics_namespace}
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: metrics-reader
  EOT
}

resource "local_file" "metrics_apply_script" {
  filename = "${path.module}/.generated-metrics-apply.sh"
  content  = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    kubectl create namespace ${var.metrics_namespace} --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f /tmp/metrics-layer.yaml

    mkdir -p ${var.metrics_export_root}
    chmod 0755 ${var.metrics_export_root}
  EOT
}

resource "null_resource" "metrics_stack" {
  triggers = {
    host             = var.host
    manifest_sha     = filesha256(local_file.metrics_manifest.filename)
    apply_script_sha = filesha256(local_file.metrics_apply_script.filename)
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
    source      = local_file.metrics_manifest.filename
    destination = "/tmp/metrics-layer.yaml"
  }

  provisioner "file" {
    source      = local_file.metrics_apply_script.filename
    destination = "/tmp/metrics-apply.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/metrics-apply.sh",
      "/tmp/metrics-apply.sh"
    ]
  }
}
