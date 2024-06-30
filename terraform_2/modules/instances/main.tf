resource "openstack_compute_instance_v2" "test_tf_vm_1" {
  name            = var.vm_name
  image_name      = var.image_name
  flavor_name     = var.flavor_name
  key_pair        = var.keypair_name
  security_groups = var.security_groups

  metadata = {
    this = "that"
  }

  network {
    name = var.network_name
  }
}

#data "openstack_images_image_ids_v2" "images" {
#  name_regex = "^Ubuntu 16\\.04.*-amd64"
#  sort       = "updated_at"
#
#  properties = {
#    key = "value"
#  }
#}

resource "openstack_images_image_v2" "cirros-062-x86_64-disk" {
  name             = "cirros-0.6.2-x86_64-disk"
  local_file_path  = "./cirros-0.6.2-x86_64-disk.img"
  min_disk_gb      = 1
  container_format = "bare"
  disk_format      = "qcow2"

  properties = {
    key = "value"
  }
}