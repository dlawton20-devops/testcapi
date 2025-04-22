terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.51.0"
    }
  }
}

provider "openstack" {
  auth_url    = var.os_auth_url
  user_name   = var.os_username
  password    = var.os_password
  tenant_name = var.os_project_name
  region      = var.os_region_name
}

# Network
resource "openstack_networking_network_v2" "cluster_network" {
  name           = "${var.cluster_name}-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "cluster_subnet" {
  name       = "${var.cluster_name}-subnet"
  network_id = openstack_networking_network_v2.cluster_network.id
  cidr       = var.subnet_cidr
  ip_version = 4
}

# Security Groups
resource "openstack_networking_secgroup_v2" "control_plane" {
  name        = "${var.cluster_name}-control-plane"
  description = "Security group for control plane nodes"
}

resource "openstack_networking_secgroup_v2" "worker" {
  name        = "${var.cluster_name}-worker"
  description = "Security group for worker nodes"
}

# SSH Key
resource "openstack_compute_keypair_v2" "cluster_key" {
  name       = "${var.cluster_name}-key"
  public_key = file(var.ssh_public_key_path)
} 