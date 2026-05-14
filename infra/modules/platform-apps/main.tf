resource "local_file" "platform_manifest" {
  filename = "${path.module}/.generated-platform.yaml"
  content  = <<-EOT
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${var.namespace}
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: mongodb
      namespace: ${var.namespace}
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: mongodb
      template:
        metadata:
          labels:
            app: mongodb
        spec:
          containers:
            - name: mongodb
              image: mongo:7
              ports:
                - containerPort: 27017
              env:
                - name: MONGO_INITDB_ROOT_USERNAME
                  value: admin
                - name: MONGO_INITDB_ROOT_PASSWORD
                  value: shadow123
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: mongodb
      namespace: ${var.namespace}
    spec:
      selector:
        app: mongodb
      ports:
        - name: mongo
          port: 27017
          targetPort: 27017
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: open5gs
      namespace: ${var.namespace}
    spec:
      replicas: ${var.platform_replicas}
      selector:
        matchLabels:
          app: open5gs
      template:
        metadata:
          labels:
            app: open5gs
        spec:
          containers:
            - name: open5gs
              image: gradiant/open5gs:latest
              imagePullPolicy: IfNotPresent
              ports:
                - containerPort: 7777
              env:
                - name: DB_URI
                  value: mongodb://admin:shadow123@mongodb.${var.namespace}.svc.cluster.local:27017
                - name: MCC
                  value: "${var.mcc}"
                - name: MNC
                  value: "${var.mnc}"
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: ueransim
      namespace: ${var.namespace}
    spec:
      replicas: ${var.platform_replicas}
      selector:
        matchLabels:
          app: ueransim
      template:
        metadata:
          labels:
            app: ueransim
        spec:
          containers:
            - name: ueransim
              image: gradiant/ueransim:latest
              imagePullPolicy: IfNotPresent
              securityContext:
                capabilities:
                  add: ["NET_ADMIN"]
              env:
                - name: MCC
                  value: "${var.mcc}"
                - name: MNC
                  value: "${var.mnc}"
              command: ["/bin/sh", "-c"]
              args:
                - |
                  ip tuntap add dev uesimtun0 mode tun || true
                  ip link set uesimtun0 up || true
                  sleep infinity
    ---
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: k6-smoke-bootstrap
      namespace: ${var.namespace}
    spec:
      backoffLimit: 0
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: k6
              image: grafana/k6:latest
              command: ["/bin/sh", "-c"]
              args:
                - "echo 'k6 ready for traffic generation';"
  EOT
}

resource "local_file" "platform_apply_script" {
  filename = "${path.module}/.generated-platform-apply.sh"
  content  = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    kubectl apply -f /tmp/platform-layer.yaml
    kubectl -n ${var.namespace} rollout status deploy/mongodb --timeout=180s
    kubectl -n ${var.namespace} rollout status deploy/open5gs --timeout=180s
    kubectl -n ${var.namespace} rollout status deploy/ueransim --timeout=180s
  EOT
}

resource "null_resource" "platform_stack" {
  triggers = {
    host             = var.host
    manifest_sha     = filesha256(local_file.platform_manifest.filename)
    apply_script_sha = filesha256(local_file.platform_apply_script.filename)
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
    source      = local_file.platform_manifest.filename
    destination = "/tmp/platform-layer.yaml"
  }

  provisioner "file" {
    source      = local_file.platform_apply_script.filename
    destination = "/tmp/platform-apply.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/platform-apply.sh",
      "/tmp/platform-apply.sh"
    ]
  }
}
