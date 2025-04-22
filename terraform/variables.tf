variable "os_auth_url" {
  description = "OpenStack authentication URL"
  type        = string
}

variable "os_username" {
  description = "OpenStack username"
  type        = string
}

variable "os_password" {
  description = "OpenStack password"
  type        = string
  sensitive   = true
}

variable "os_project_name" {
  description = "OpenStack project name"
  type        = string
}

variable "os_region_name" {
  description = "OpenStack region name"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR for the cluster subnet"
  type        = string
  default     = "192.168.0.0/24"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key"
  type        = string
} 