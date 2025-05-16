variable "rancher_api_url" {}
variable "rancher_token" {}
variable "project_id" {}

provider "rancher2" {
  api_url   = var.rancher_api_url
  token_key = var.rancher_token
  insecure  = true
}

resource "rancher2_catalog_v2" "rook_ceph_operator" {
  name     = "rook-ceph"
  repo_url = "https://charts.rook.io/release"
  branch   = "main"
}

resource "rancher2_catalog_v2" "rook_ceph_cluster" {
  name     = "rook-ceph-cluster"
  repo_url = "https://charts.rook.io/release"
  branch   = "main"
}

resource "rancher2_namespace" "rook_ceph" {
  name       = "rook-ceph"
  project_id = var.project_id
}

locals {
  rook_ceph_operator_values = templatefile("${path.module}/values-operator.yaml.tftpl", {})
  rook_ceph_cluster_values  = templatefile("${path.module}/values-cluster.yaml.tftpl", {})
}

resource "rancher2_app_v2" "rook_ceph_operator" {
  name          = "rook-ceph-operator"
  namespace     = rancher2_namespace.rook_ceph.name
  project_id    = var.project_id
  repo_name     = rancher2_catalog_v2.rook_ceph_operator.name
  chart_name    = "rook-ceph"
  chart_version = "1.12.0"
  values        = local.rook_ceph_operator_values
}

resource "rancher2_app_v2" "rook_ceph_cluster" {
  name          = "rook-ceph-cluster"
  namespace     = rancher2_namespace.rook_ceph.name
  project_id    = var.project_id
  repo_name     = rancher2_catalog_v2.rook_ceph_cluster.name
  chart_name    = "rook-ceph-cluster"
  chart_version = "1.12.0"
  values        = local.rook_ceph_cluster_values
  depends_on    = [rancher2_app_v2.rook_ceph_operator]
} 
