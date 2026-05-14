locals {
  mirror_block = var.enable_shadow_mirroring ? join("\n", [
    "mirror:",
    "  host: api.${var.namespace}.svc.cluster.local",
    "  subset: v2",
    "mirrorPercentage:",
    "  value: ${format("%.1f", var.mirror_percentage)}",
  ]) : ""
}

resource "local_file" "apps_workloads_manifest" {
  filename = "${path.module}/.generated-apps-workloads.yaml"
  content  = <<-EOT
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${var.namespace}
      labels:
        istio-injection: enabled
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: api-prod
      namespace: ${var.namespace}
      labels:
        app: api
        version: v1
    spec:
      replicas: ${var.app_prod_replicas}
      selector:
        matchLabels:
          app: api
          version: v1
      template:
        metadata:
          labels:
            app: api
            version: v1
        spec:
          containers:
            - name: api
              image: hashicorp/http-echo:1.0
              args: ["-text=prod-v1"]
              ports:
                - containerPort: 5678
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: api-shadow
      namespace: ${var.namespace}
      labels:
        app: api
        version: v2
    spec:
      replicas: ${var.app_shadow_replicas}
      selector:
        matchLabels:
          app: api
          version: v2
      template:
        metadata:
          labels:
            app: api
            version: v2
        spec:
          containers:
            - name: api
              image: hashicorp/http-echo:1.0
              args: ["-text=shadow-v2"]
              ports:
                - containerPort: 5678
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: api
      namespace: ${var.namespace}
    spec:
      selector:
        app: api
      ports:
        - name: http
          port: 80
          targetPort: 5678
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: diff-analyzer
      namespace: ${var.namespace}
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: diff-analyzer
      template:
        metadata:
          labels:
            app: diff-analyzer
        spec:
          containers:
            - name: diff-analyzer
              image: mendhak/http-https-echo:31
              ports:
                - containerPort: 8080
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: diff-analyzer
      namespace: ${var.namespace}
    spec:
      selector:
        app: diff-analyzer
      ports:
        - name: http
          port: 8080
          targetPort: 8080
  EOT
}

resource "local_file" "apps_routing_manifest" {
  filename = "${path.module}/.generated-apps-routing.yaml"
  content  = <<-EOT
    apiVersion: networking.istio.io/v1beta1
    kind: DestinationRule
    metadata:
      name: api-dr
      namespace: ${var.namespace}
    spec:
      host: api.${var.namespace}.svc.cluster.local
      subsets:
        - name: v1
          labels:
            version: v1
        - name: v2
          labels:
            version: v2
    ---
    apiVersion: networking.istio.io/v1beta1
    kind: VirtualService
    metadata:
      name: api-shadow-vs
      namespace: ${var.namespace}
    spec:
      hosts:
        - api.${var.namespace}.svc.cluster.local
      http:
        - route:
            - destination:
                host: api.${var.namespace}.svc.cluster.local
                subset: v1
              weight: 100
${indent(10, local.mirror_block)}
  EOT
}

resource "local_file" "apps_apply_script" {
  filename = "${path.module}/.generated-apps-apply.sh"
  content  = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    kubectl apply -f /tmp/apps-workloads.yaml
    kubectl apply -f /tmp/apps-routing.yaml

    kubectl -n ${var.namespace} rollout status deploy/api-prod --timeout=180s
    kubectl -n ${var.namespace} rollout status deploy/api-shadow --timeout=180s
    kubectl -n ${var.namespace} rollout status deploy/diff-analyzer --timeout=180s
  EOT
}

resource "null_resource" "apps_stack" {
  triggers = {
    host            = var.host
    workloads_sha   = filesha256(local_file.apps_workloads_manifest.filename)
    routing_sha     = filesha256(local_file.apps_routing_manifest.filename)
    apply_script_sha = filesha256(local_file.apps_apply_script.filename)
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
    source      = local_file.apps_workloads_manifest.filename
    destination = "/tmp/apps-workloads.yaml"
  }

  provisioner "file" {
    source      = local_file.apps_routing_manifest.filename
    destination = "/tmp/apps-routing.yaml"
  }

  provisioner "file" {
    source      = local_file.apps_apply_script.filename
    destination = "/tmp/apps-apply.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/apps-apply.sh",
      "/tmp/apps-apply.sh"
    ]
  }
}
