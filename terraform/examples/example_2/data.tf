data "openstack_networking_network_v2" "pub_net" {
  name = var.pub_net
}

data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}