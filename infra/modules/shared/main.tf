resource "local_file" "shared_bootstrap_script" {
  filename = "${path.module}/.generated-shared.sh"
  content  = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace ${var.apps_namespace} --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace ${var.open5gs_namespace} --dry-run=client -o yaml | kubectl apply -f -

    helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update

    helm upgrade --install istio-base istio/base \
      --namespace istio-system \
      --version ${var.istio_version} \
      --wait

    helm upgrade --install istiod istio/istiod \
      --namespace istio-system \
      --version ${var.istio_version} \
      --wait

    kubectl label namespace ${var.apps_namespace} istio-injection=enabled --overwrite
    kubectl label namespace ${var.open5gs_namespace} istio-injection=disabled --overwrite

    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
      --namespace monitoring \
      --version ${var.kube_prom_stack_version} \
      --set grafana.enabled=true \
      --set alertmanager.enabled=false \
      --set prometheus.prometheusSpec.retention=24h \
      --wait
  EOT
}

resource "null_resource" "shared_stack" {
  triggers = {
    host       = var.host
    script_sha = filesha256(local_file.shared_bootstrap_script.filename)
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
    source      = local_file.shared_bootstrap_script.filename
    destination = "/tmp/shadow-shared.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/shadow-shared.sh",
      "/tmp/shadow-shared.sh"
    ]
  }
}
