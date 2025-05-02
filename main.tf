terraform {
  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 1.25.0"
    }
  }
}

provider "rancher2" {
  api_url   = var.rancher_api_url
  token_key = var.rancher_token
  insecure  = true
}

resource "rancher2_cluster_v2" "downstream" {
  name        = var.cluster_name
  description = "Downstream cluster with proxy mode and Harbor cache"
  kubernetes_version = "v1.29.1+rke2r1"

  rke_config {
    machine_pools {
      name = "control-plane"
      cloud_credential_secret_name = "openstack-credential"
      control_plane_role = true
      etcd_role = true
      worker_role = false
      quantity = var.control_plane_count
      machine_config {
        kind = "OpenstackConfig"
        openstack_config {
          auth_url    = var.openstack_auth_url
          username    = var.openstack_username
          password    = var.openstack_password
          tenant_name = var.openstack_tenant_name
          region      = var.openstack_region
          image_name  = var.openstack_image_name
          flavor_name = var.openstack_flavor_name
          network_name = var.openstack_network_name
        }
      }
      machine_selector_config {
        config = {
          "cloud-init" = <<-EOT
            #cloud-config
            write_files:
            - path: /etc/rancher/rke2/registries.yaml
              owner: root:root
              permissions: '0644'
              content: |
                mirrors:
                  "docker.io":
                    endpoint:
                      - "https://registry.dci.test.com"
                  "rke2-registry.rancher.io":
                    endpoint:
                      - "https://registry.dci.test.com"
                configs:
                  "registry.dci.test.com":
                    auth:
                      username: "${var.harbor_username}"
                      password: "${var.harbor_password}"
                    tls:
                      insecure_skip_verify: true
          EOT
        }
      }
    }

    machine_pools {
      name = "worker"
      cloud_credential_secret_name = "openstack-credential"
      control_plane_role = false
      etcd_role = false
      worker_role = true
      quantity = var.worker_count
      machine_config {
        kind = "OpenstackConfig"
        openstack_config {
          auth_url    = var.openstack_auth_url
          username    = var.openstack_username
          password    = var.openstack_password
          tenant_name = var.openstack_tenant_name
          region      = var.openstack_region
          image_name  = var.openstack_image_name
          flavor_name = var.openstack_flavor_name
          network_name = var.openstack_network_name
        }
      }
      machine_selector_config {
        config = {
          "cloud-init" = <<-EOT
            #cloud-config
            write_files:
            - path: /etc/rancher/rke2/registries.yaml
              owner: root:root
              permissions: '0644'
              content: |
                mirrors:
                  "docker.io":
                    endpoint:
                      - "https://registry.dci.test.com"
                  "rke2-registry.rancher.io":
                    endpoint:
                      - "https://registry.dci.test.com"
                configs:
                  "registry.dci.test.com":
                    auth:
                      username: "${var.harbor_username}"
                      password: "${var.harbor_password}"
                    tls:
                      insecure_skip_verify: true
          EOT
        }
      }
    }
  }
} 
