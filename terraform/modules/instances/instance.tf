resource "openstack_compute_instance_v2" "vm" {
  for_each     = { for k, v in local.instances : v.name => v
#  if try(v.image_name, null) != null
  }
#  for_each = var.VMs # == {} ? null : var.VMs
  name                        = each.value.name
  image_name                  = each.value.image_name
  flavor_name                 = each.value.flavor_name
  key_pair                    = each.value.keypair_name
  security_groups             = each.value.security_groups
  availability_zone_hints     = each.value.az_hint
  metadata = {
    test_meta = "Created by Terraform"
  }
  block_device {
    uuid                  = data.openstack_images_image_v2.image_id[each.key].id
    source_type           = "image"
    volume_size           = each.value.volume_size
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
  network {
    name = each.value.network_name
  }
}

data "openstack_images_image_v2" "image_id" {
  for_each    = { for k, v in local.instances : v.name => v }
  name        = each.value.image_name
#  most_recent = true
#
#  properties = {
#    key = "value"
#  }
}

#resource "openstack_compute_instance_v2" "vm" {
##  for_each = var.VMs # == {} ? null : var.VMs
#  count = var.vm_qty
#  name                        = format("%s-%02d", var.vm_name, count.index+1)
#  image_name                  = var.image_name
#  flavor_name                 = var.flavor_name
#  key_pair                    = var.keypair_name
#  security_groups             = var.security_groups
#  availability_zone_hints     = var.az_hint
#  metadata = {
#    this = "that"
#  }
#  block_device {
#    uuid                  = var.image_name
#    source_type           = "image"
#    volume_size           = var.volume_size
#    boot_index            = 0
##    destination_type      = "volume"
#    delete_on_termination = true
#  }
#  network {
#    name = var.network_name
#  }
#}

#data "openstack_images_image_v2" "image" {
#  name        = each.image_name
#  most_recent = true
#}