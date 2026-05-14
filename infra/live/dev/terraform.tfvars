environment = "dev"

debian_host = "203.0.113.10"
ssh_user    = "debian"
ssh_port    = 22

# Option A: use existing key
ssh_private_key_path = "/Users/jus/.ssh/id_ed25519"

# Option B: generate key with Terraform (set true and add public key on server)
# generate_ssh_key                 = true
# generated_private_key_output_path = ".generated/dev-shadow-key.pem"

k3s_version                 = "v1.30.2+k3s2"
install_multus              = true
istio_version               = "1.22.2"
kube_prom_stack_version     = "58.5.1"
apps_namespace              = "shadow-apps"
open5gs_namespace           = "telecom"
mcc                         = "001"
mnc                         = "01"
platform_replicas           = 1
app_prod_replicas           = 1
app_shadow_replicas         = 1
enable_shadow_mirroring     = true
mirror_percentage           = 100
