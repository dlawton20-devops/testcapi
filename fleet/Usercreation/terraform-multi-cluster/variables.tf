# Terraform Variables for Multi-Cluster Rancher User Setup

variable "rancher_api_url" {
  description = "Rancher API URL"
  type        = string
  default     = "https://rancher.your-domain.com"
}

variable "rancher_token" {
  description = "Rancher API token"
  type        = string
  sensitive   = true
}

variable "rancher_insecure" {
  description = "Allow insecure connections to Rancher"
  type        = bool
  default     = false
}

variable "username" {
  description = "Username for the local user"
  type        = string
  default     = "lma-user"
}

variable "password" {
  description = "Password for the local user"
  type        = string
  sensitive   = true
}

variable "display_name" {
  description = "Display name for the user"
  type        = string
  default     = "LMA User"
}

variable "email" {
  description = "Email for the user"
  type        = string
  default     = "lma-user@example.com"
}

variable "exclude_clusters" {
  description = "List of cluster IDs to exclude from permissions"
  type        = list(string)
  default     = []
}

variable "exclude_projects" {
  description = "List of project IDs to exclude from permissions"
  type        = list(string)
  default     = []
}