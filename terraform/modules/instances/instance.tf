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
  metadata                    = each.value.metadata
  user_data                   = each.value.user_data

 block_device {
#    uuid                  = openstack_blockstorage_volume_v3.fc_hdd_sda[count.index].id
#    name         = "fc_hdd_boot"
    uuid                  = data.openstack_images_image_v2.image_id[each.key].id
    volume_size           = each.value.boot_volume_size
    source_type           = "image"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = each.value.boot_volume_delete_on_termination
#    device_name           = "/dev/vda"
  }

dynamic block_device {
    for_each = [for volume in each.value.disks: {
#      for_each = {}
#      for key, value in var.volume : key
        boot_index = try(volume.boot_index, -1)
        size = try(volume.size, var.default_volume_size)
        delete_on_termination = try(volume.delete_on_termination, var.default_delete_on_termination)
        device_name           = try(volume.device_name, null)
    }]
    content {
#        uuid = "volume-${each.value.base_name}-${block_device.value.boot_index}"
        source_type           = "blank"
        volume_size           = block_device.value.size
        boot_index            = block_device.value.boot_index
        destination_type      = "volume"
        delete_on_termination = block_device.value.delete_on_termination
        device_name           = block_device.value.device_name
    }
 }

  network {
    name = each.value.network_name
  }
  depends_on = [
    openstack_compute_flavor_v2.flavor
  ]
}

resource "openstack_compute_flavor_v2" flavor {
#  for_each    = { for k, v in local.instances : v.name => v }
  for_each = var.VMs
  name        = "${each.key}-flavor"
#  flavor_id  = "2c-2r"
#  name       = "2c-2r"
#  vcpus      = try(instance.flavor.vcpus, var.default_flavor.vcpus)
#  ram        = try(instance.falvor.ram, var.default_flavor.ram)
  vcpus       = try(each.value.flavor.vcpus, var.default_flavor.vcpus) #each.value.flavor.vcpus
  ram         = try(each.value.flavor.ram, var.default_flavor.ram)
  disk        = "0"
  is_public   = "true"
  extra_specs = try(each.value.flavor.extra_specs, var.default_flavor.extra_specs)
#  {
#    "hw:mem_page_size" = "large"
#  }
}

data "openstack_images_image_v2" "image_id" {
  for_each    = { for k, v in local.instances : v.name => v }
  name        = each.value.image_name
}

#security group
resource "openstack_compute_secgroup_v2" "secgroup" {
 name = "terraform_security_group"
 description = "Created by test terraform security group"
# rule {
#  from_port = 22
#  to_port = 22
#  ip_protocol = "tcp"
#  cidr = "0.0.0.0/0"
# }
 rule {
  from_port = -1
  to_port = -1
  ip_protocol = "icmp"
  cidr = "0.0.0.0/0"
 }
 rule {
  from_port = 1
  to_port = 65535
  ip_protocol = "udp"
  cidr = "0.0.0.0/0"
 }
 rule {
  from_port = 1
  to_port = 65535
  ip_protocol = "tcp"
  cidr = "0.0.0.0/0"
 }
}

#key_pair
resource "openstack_compute_keypair_v2" "keypair" {
  name        = "terraform_keypair"
  public_key  = var.default_puplic_key
}
