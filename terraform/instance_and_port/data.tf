data "openstack_networking_network_v2" "network" {
  name = var.network_name
}

data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}