resource "openstack_compute_instance_v2" "vm" {
  name                        = format("%s-%02d", var.vm_name, count.index+1)
  image_name                  = var.image_name
  flavor_name                 = var.flavor_name
  key_pair                    = var.keypair_name
  security_groups             = var.security_groups
  availability_zone_hints     = var.az_hints
  count = var.vm_qty
  metadata = {
    this = "that"
  }
  block_device {
    uuid                  = var.image_name
    source_type           = "image"
    volume_size           = var.volume_size
    boot_index            = 0
#    destination_type      = "volume"
    delete_on_termination = true
  }
  network {
    name = var.network_name
  }
}

data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true

#  properties = {
#    key = "value"
#  }
}

#output "az" {
#  value = openstack_compute_instance_v2.vm.availability_zone
#}

#data "openstack_images_image_ids_v2" "images" {
#  name_regex = "^Ubuntu 16\\.04.*-amd64"
#  sort       = "updated_at"
#
#  properties = {
#    key = "value"
#  }
#}

#resource "openstack_images_image_v2" "cirros-062-x86_64-disk" {
#  name             = "cirros-0.6.2-x86_64-disk"
#  local_file_path  = "./cirros-0.6.2-x86_64-disk.img"
#  min_disk_gb      = 1
#  container_format = "bare"
#  disk_format      = "qcow2"
#
#  properties = {
#    key = "value"
#  }
#}