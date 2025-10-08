# Rancher User Creation with Terraform
# This creates a local user in Rancher

terraform {
  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 3.0"
    }
  }
}

# Configure the Rancher2 Provider
provider "rancher2" {
  api_url   = var.rancher_api_url
  token_key = var.rancher_token
  insecure  = var.rancher_insecure
}

# Create a local user
resource "rancher2_user" "local_user" {
  username = var.username
  password = var.password
  enabled  = true
  name     = var.display_name
  email    = var.email
}

# Global member role binding
resource "rancher2_global_role_binding" "user_global_member" {
  global_role_id = "user"
  user_id        = rancher2_user.local_user.id
}

# Cluster member role binding
resource "rancher2_cluster_role_template_binding" "user_cluster_member" {
  cluster_id      = var.cluster_id
  role_template_id = "cluster-member"
  user_id         = rancher2_user.local_user.id
}

# Cluster viewer role binding
resource "rancher2_cluster_role_template_binding" "user_cluster_viewer" {
  cluster_id      = var.cluster_id
  role_template_id = "cluster-view"
  user_id         = rancher2_user.local_user.id
}

# Create LMA project
resource "rancher2_project" "lma_project" {
  name       = "lma"
  cluster_id = var.cluster_id
  description = "LMA (Logging, Monitoring, Alerting) Project"
}

# Add cattle-monitoring-system namespace to project
resource "rancher2_namespace" "cattle_monitoring" {
  name       = "cattle-monitoring-system"
  project_id = rancher2_project.lma_project.id
  labels = {
    "management.cattle.io/system" = "true"
  }
}

# Add cattle-logging-system namespace to project
resource "rancher2_namespace" "cattle_logging" {
  name       = "cattle-logging-system"
  project_id = rancher2_project.lma_project.id
  labels = {
    "management.cattle.io/system" = "true"
  }
}

# Project member role binding
resource "rancher2_project_role_template_binding" "user_project_member" {
  project_id      = rancher2_project.lma_project.id
  role_template_id = "project-member"
  user_id         = rancher2_user.local_user.id
}

# Project viewer role binding
resource "rancher2_project_role_template_binding" "user_project_viewer" {
  project_id      = rancher2_project.lma_project.id
  role_template_id = "project-view"
  user_id         = rancher2_user.local_user.id
}

# Output the user ID for use in other scripts
output "user_id" {
  value = rancher2_user.local_user.id
}

output "project_id" {
  value = rancher2_project.lma_project.id
}

output "cluster_id" {
  value = var.cluster_id
}