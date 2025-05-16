resource "openstack_blockstorage_volume_v3" "my_k8s_volume" {
  name = "my-k8s-volume"
  size = 20 # Size in GB
}

resource "openstack_compute_instance_v2" "k8s_node" {
  name            = "k8s-node-1"
  flavor_name     = var.flavor_name
  image_name      = var.image_name
  key_pair        = var.key_pair
  security_groups = var.security_groups
  network {
    uuid = var.network_id
  }

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.my_k8s_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 1
    delete_on_termination = true
    device                = "/dev/vdb"
  }

  user_data = <<-EOF
    #cloud-config
    runcmd:
      - sudo mkfs.ext4 /dev/vdb
  EOF
}

variable "flavor_name" {}
variable "image_name" {}
variable "key_pair" {}
variable "security_groups" { type = list(string) }
variable "network_id" {} 