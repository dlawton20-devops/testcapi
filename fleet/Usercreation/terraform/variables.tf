# Terraform Variables for Rancher User Setup

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

variable "cluster_id" {
  description = "Target cluster ID"
  type        = string
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