variable "rancher_api_url" {}
variable "rancher_token" {}
variable "project_id" {}

provider "rancher2" {
  api_url   = var.rancher_api_url
  token_key = var.rancher_token
  insecure  = true
}

resource "rancher2_catalog_v2" "rook_ceph" {
  name     = "rook-ceph"
  repo_url = "https://charts.rook.io/release"
  branch   = "main"
}

resource "rancher2_namespace" "rook_ceph" {
  name       = "rook-ceph"
  project_id = var.project_id
}

locals {
  rook_ceph_values = templatefile("${path.module}/values.yaml.tftpl", {})
}

resource "rancher2_app_v2" "rook_ceph" {
  name          = "rook-ceph"
  namespace     = rancher2_namespace.rook_ceph.name
  project_id    = var.project_id
  repo_name     = rancher2_catalog_v2.rook_ceph.name
  chart_name    = "rook-ceph"
  chart_version = "1.12.0"
  values        = local.rook_ceph_values
} 