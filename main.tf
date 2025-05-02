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

resource "rancher2_cluster" "downstream" {
  name        = var.cluster_name
  description = "Downstream cluster with proxy mode and Harbor cache"

  rke_config {
    network {
      plugin = "canal"
    }

    # Configure containerd to use Harbor as pull-through cache
    services {
      kubelet {
        extra_args = {
          "http-proxy"  = var.http_proxy
          "https-proxy" = var.https_proxy
          "no-proxy"    = "${var.no_proxy},registry.dci.test.com"
        }
      }
      containerd {
        extra_args = {
          "config-file" = "/etc/rancher/rke2/registries.yaml"
        }
      }
    }

    # Add registries.yaml as a file
    files {
      name     = "registries.yaml"
      contents = templatefile("${path.module}/registries.yaml", {
        HARBOR_USERNAME = var.harbor_username
        HARBOR_PASSWORD = var.harbor_password
      })
      path     = "/etc/rancher/rke2/registries.yaml"
    }
  }
}

# Node template for OpenStack
resource "rancher2_node_template" "openstack" {
  name         = "openstack-template"
  description  = "OpenStack node template"
  driver_id    = "openstack"
  
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

# Node pool configuration
resource "rancher2_node_pool" "control_plane" {
  cluster_id       = rancher2_cluster.downstream.id
  name             = "control-plane"
  hostname_prefix  = "control-"
  node_template_id = rancher2_node_template.openstack.id
  quantity         = var.control_plane_count
  control_plane    = true
  etcd             = true
  worker           = false
}

resource "rancher2_node_pool" "worker" {
  cluster_id       = rancher2_cluster.downstream.id
  name             = "worker"
  hostname_prefix  = "worker-"
  node_template_id = rancher2_node_template.openstack.id
  quantity         = var.worker_count
  control_plane    = false
  etcd             = false
  worker           = true
} 
