

resource "openstack_compute_instance_v2" "vm" {
  for_each     = { for k, v in local.instances : v.name => v
#  if try(v.image_name, null) != null
  }
#  for_each = var.VMs # == {} ? null : var.VMs
  name                        = each.value.name
  image_name                  = each.value.image_name
  flavor_name                 = each.value.flavor_name == "" ? "${each.value.base_name}-flavor" : each.value.flavor_name
#  flavor_id                   = openstack_compute_flavor_v2.flavor[each.value].id
  key_pair                    = each.value.keypair_name == null ? openstack_compute_keypair_v2.keypair.name : each.value.keypair_name
  security_groups             = each.value.security_groups == null ? [openstack_compute_secgroup_v2.secgroup.name] : each.value.security_groups
  availability_zone_hints     = each.value.az_hint
  metadata = {
    test_meta = "Created by Terraform"
  }
  scheduler_hints {
     group = each.value.server_group == null ? "" : module.server_groups[each.value.server_group].srvgrp_id
#    group                  = each.value.server_group_name.id
  }
#  dynamic "block_device" {
#    for_each = each.value.disk
#    content {
#      uuid                  = block_device.key == "sda" ? data.openstack_images_image_v2.image_id[each.key].id : null
#      source_type           = block_device.key == "sda" ? "image" : "blank"
#      boot_index            = block_device.key == "sda" ? 0 : 1
#      volume_size           = block_device.value
#      destination_type      = "volume"
#      delete_on_termination = true
#    }
 block_device {
#    uuid                  = openstack_blockstorage_volume_v3.fc_hdd_sda[count.index].id
#    name         = "fc_hdd_boot"
    uuid                  = data.openstack_images_image_v2.image_id[each.key].id
    volume_size           = each.value.boot_volume_size
    source_type           = "image"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = false
  }
#  dynamic "block_device" {
##    for iter in range(1, instance.vm_qty+1) : {
  ##    volume = flatten([
  ##      for instance_key, instance in var.VMs : [
  ##  for iter in range(1, instance.vm_qty+1) : {
  ##      ]
  ##    }
#    for_each = each.value.disks
#      content {
#      #      uuid                  = block_device.key == "sda" ? data.openstack_images_image_v2.image_id[each.key].id : null
#      #      source_type           = block_device.key == "sda" ? "image" : "blank"
#      #      boot_index            = block_device.key == "sda" ? 0 : 1
#      boot_index            = volume_size = block_device.value
#      destination_type      = "volume"
#      delete_on_termination = true
#    }
#      }
#      }
dynamic block_device {
    for_each = [for volume in each.value.disks: {
            boot_index = volume.boot_index
            size = volume.size
    }]
    content {
#        uuid = "volume-${each.value.base_name}-${block_device.value.boot_index}"
        source_type           = "blank"
        volume_size           = block_device.value.size
        boot_index            = block_device.value.boot_index
        destination_type      = "volume"
        delete_on_termination = true
    }
 }

  network {
    name = each.value.network_name
  }
  depends_on = [
    openstack_compute_flavor_v2.flavor
  ]
}

#module "server_groups" {
#  source         = "../../modules/server_groups"
#  server_group   = var.server_group
#}

resource "openstack_compute_flavor_v2" flavor {
#  for_each    = { for k, v in local.instances : v.name => v }
  for_each = var.VMs
  name        = "${each.key}-flavor"
#  flavor_id = "2c-2r"
#  name      = "2c-2r"
#  vcpus     = try(instance.flavor.vcpus, var.default_flavor.vcpus)
#  ram       = try(instance.falvor.ram, var.default_flavor.ram)
  vcpus     = try(each.value.flavor.vcpus, var.default_flavor.vcpus) #each.value.flavor.vcpus
  ram       = try(each.value.flavor.ram, var.default_flavor.ram)
  disk      = "0"
  is_public = "true"
}

data "openstack_images_image_v2" "image_id" {
  for_each    = { for k, v in local.instances : v.name => v }
  name        = each.value.image_name
}

#resource "openstack_blockstorage_volume_v3" "volume" {
##  for_each = { for volume_key, volume in local.instance.disks }
#  for_each    = { for k, v in local.instances.disks : v.name => v }
##  for_each = local.instances
##  for_each    = { for k, v in local.instances : v.name => v }
#  name         = each.value.disk"fc_hdd_sdd"
#  size                 = 1
#  enable_online_resize = true
#  lifecycle {
#    ignore_changes  = [image_id, volume_type]
#  }
#}
#
#resource "openstack_compute_volume_attach_v2" "volume_attach" {
#  count = var.qty
#  instance_id = openstack_compute_instance_v2.fc_hdd[count.index].id
#  volume_id   = openstack_blockstorage_volume_v3.fc_hdd_sda[count.index].id
#}

#security group
resource "openstack_compute_secgroup_v2" "secgroup" {
 name = "terraform_security_group"
 description = "Created by test terraform security group"
 rule {
  from_port = 22
  to_port = 22
  ip_protocol = "tcp"
  cidr = "0.0.0.0/0"
 }
 rule {
  from_port = -1
  to_port = -1
  ip_protocol = "icmp"
  cidr = "0.0.0.0/0"
 }
}

#key_pair
resource "openstack_compute_keypair_v2" "keypair" {
  name        = "terraform_keypair"
  public_key  = var.default_puplic_key
}
