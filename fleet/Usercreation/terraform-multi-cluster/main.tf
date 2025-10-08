# Multi-Cluster Rancher User Setup with Terraform
# This creates user permissions across ALL clusters in Rancher

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

# Data source to get all clusters
data "rancher2_clusters" "all" {}

# Data source to get all projects
data "rancher2_projects" "all" {}

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

# Create cluster permissions for ALL clusters
resource "rancher2_cluster_role_template_binding" "user_cluster_member" {
  for_each = {
    for cluster in data.rancher2_clusters.all.clusters : cluster.id => cluster
  }
  
  cluster_id      = each.value.id
  role_template_id = "cluster-member"
  user_id         = rancher2_user.local_user.id
  
  depends_on = [rancher2_user.local_user]
}

resource "rancher2_cluster_role_template_binding" "user_cluster_viewer" {
  for_each = {
    for cluster in data.rancher2_clusters.all.clusters : cluster.id => cluster
  }
  
  cluster_id      = each.value.id
  role_template_id = "cluster-view"
  user_id         = rancher2_user.local_user.id
  
  depends_on = [rancher2_user.local_user]
}

# Create project permissions for ALL projects
resource "rancher2_project_role_template_binding" "user_project_member" {
  for_each = {
    for project in data.rancher2_projects.all.projects : project.id => project
  }
  
  project_id      = each.value.id
  role_template_id = "project-member"
  user_id         = rancher2_user.local_user.id
  
  depends_on = [rancher2_user.local_user]
}

resource "rancher2_project_role_template_binding" "user_project_viewer" {
  for_each = {
    for project in data.rancher2_projects.all.projects : project.id => project
  }
  
  project_id      = each.value.id
  role_template_id = "project-view"
  user_id         = rancher2_user.local_user.id
  
  depends_on = [rancher2_user.local_user]
}

# Outputs
output "user_id" {
  value = rancher2_user.local_user.id
}

output "clusters_processed" {
  value = length(data.rancher2_clusters.all.clusters)
}

output "projects_processed" {
  value = length(data.rancher2_projects.all.projects)
}

output "cluster_details" {
  value = {
    for cluster in data.rancher2_clusters.all.clusters : cluster.id => {
      name = cluster.name
      display_name = cluster.display_name
      state = cluster.state
    }
  }
}

output "project_details" {
  value = {
    for project in data.rancher2_projects.all.projects : project.id => {
      name = project.name
      display_name = project.display_name
      cluster_id = project.cluster_id
    }
  }
}