# Only need control_platform project name - tenant project comes from OS_PROJECT_NAME env var
variable "control_platform_project_name" {
  description = "OpenStack project name for control plane and platform worker networks"
  type        = string
}

variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name = string
    controlplane = object({
      network_name = string
    })
    platformworker = object({
      network_name = string
    })
    tenantworker0 = object({
      network_name = string
      override_quantity_per_az = map(number)
    })
    tenantworker1 = object({
      network_name = string
      override_quantity_per_az = map(number)
    })
  })
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "ntp_site" {
  description = "Site identifier for NTP server selection (e.g., b65nc01, dyxnc01, stanc01)"
  type        = string
}

