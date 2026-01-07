locals {
  tenantworker0 = {
    for az in var.availability_zones :
    az => lookup(var.cluster.tenantworker0.override_quantity_per_az, az, null)
    if lookup(var.cluster.tenantworker0.override_quantity_per_az, az, null) != null
  }
  
  tenantworker1 = {
    for az in var.availability_zones :
    az => lookup(var.cluster.tenantworker1.override_quantity_per_az, az, null)
    if lookup(var.cluster.tenantworker1.override_quantity_per_az, az, null) != null
  }
  
  audit_policy = chomp(templatefile("${path.module}/audit-policy.yaml", {}))
  
  worker_networks = {
    controlplane   = var.cluster.controlplane.network_name
    platformworker = var.cluster.platformworker.network_name
    tenantworker0  = var.cluster.tenantworker0.network_name
    tenantworker1  = var.cluster.tenantworker1.network_name
  }
  
  # Define a local variable for the cluster name, sourced from the input
  cluster_name = var.cluster.name
  
  # Site → NTP IPs mapping
  ntp_by_site = {
    dyxnc01 = ["10.15.240.221", "10.15.240.222"]
    stanc01 = ["10.15.224.221", "10.15.224.222"]
    b65nc01 = ["10.2.118.222"] # single: duplicate
  }
  
  # Selected NTP IPs based on site
  ntp_ips = lookup(local.ntp_by_site, var.ntp_site, [])
}

# Loading a template file for each worker network and passing NTP IPs as variables
data "template_file" "worker_templates" {
  for_each = local.worker_networks
  
  template = file("${path.module}/user_data.yaml")
  
  vars = {
    # Use NTP IPs from selected site
    ntpip1 = length(local.ntp_ips) > 0 ? local.ntp_ips[0] : ""
    ntpip2 = length(local.ntp_ips) > 1 ? local.ntp_ips[1] : (length(local.ntp_ips) > 0 ? local.ntp_ips[0] : "")
  }
}

