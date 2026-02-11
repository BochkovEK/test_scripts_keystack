resource "openstack_compute_aggregate_v2" "aggr" {
  for_each = var.AZs
  name   = each.key
  zone   = each.value.az_name #"az_1"
  metadata = {
    test_meta = "Created by Terraform AZ_module"
  }
  hosts = each.value.hosts_list
}

resource "openstack_compute_servergroup_v2" "vm_group" {
  for_each = {
    for vm_key, vm in var.VMs : vm_key => vm.server_group
    if try(vm.server_group, null) != null
  }

  name     = each.value.name
  policies = [each.value.policy]
}

#resource "openstack_blockstorage_volume_v3" "root_volume" {
#  for_each = { for k, v in local.instances : v.name => v }
#
#  name        = "${each.value.name}-root"
#  size        = each.value.boot_volume_size
#  volume_type = var.default_volume_type
##  image_id    = data.openstack_images_image_v2.image_id[each.key].id
#}

resource "openstack_blockstorage_volume_v3" "data_volumes" {
  for_each = { for vol in local.all_data_volumes : "${vol.vm_name}-${vol.name}" => vol }

  name        = each.value.name
  size        = each.value.size
  volume_type = var.default_volume_type
}

resource "openstack_compute_instance_v2" "vm" {
  for_each = { for k, v in local.instances : v.name => v }

  name                        = each.value.name
#  image_name                  = each.value.image_name
  flavor_name                 = each.value.flavor_name == "" ? "${each.value.base_name}-flavor" : each.value.flavor_name
  key_pair                    = each.value.keypair_name == null ? openstack_compute_keypair_v2.keypair.name : each.value.keypair_name
  security_groups             = each.value.security_groups == null ? [openstack_compute_secgroup_v2.secgroup.name] : each.value.security_groups
  availability_zone_hints     = each.value.az_hint
  metadata                    = each.value.metadata
  user_data                   = each.value.user_data
  config_drive                = each.value.config_drive

#  block_device {
#    uuid                  = openstack_blockstorage_volume_v3.root_volume[each.key].id
#    source_type           = "volume"
#    boot_index            = 0
#    destination_type      = "volume"
#    delete_on_termination = each.value.boot_volume_delete_on_termination
#  }
  # Bootable disk
  block_device {
    uuid                  = data.openstack_images_image_v2.image_id[each.key].id
    source_type           = "image"
    destination_type      = "volume"
    boot_index            = 0
    volume_size           = each.value.boot_volume_size
    volume_type           = var.default_volume_type
    delete_on_termination = each.value.boot_volume_delete_on_termination
  }

  dynamic "block_device" {
    for_each = { for vol in local.all_data_volumes : vol.name => vol if vol.vm_name == each.value.name }
    content {
      uuid                  = openstack_blockstorage_volume_v3.data_volumes["${each.value.name}-${block_device.value.name}"].id
      source_type           = "volume"
      boot_index            = block_device.value.boot_index
      destination_type      = "volume"
      delete_on_termination = block_device.value.delete_on_termination
    }
  }

  network {
    name = each.value.network_name
  }

  depends_on = [
    openstack_blockstorage_volume_v3.root_volume,
    openstack_blockstorage_volume_v3.data_volumes
  ]
}

resource "openstack_compute_flavor_v2" flavor {
  for_each = var.VMs
  name        = "${each.key}-flavor"
  vcpus       = try(each.value.flavor.vcpus, var.default_flavor.vcpus) #each.value.flavor.vcpus
  ram         = try(each.value.flavor.ram, var.default_flavor.ram)
  disk        = "0"
  is_public   = "true"
  extra_specs = try(each.value.flavor.extra_specs, var.default_flavor.extra_specs)
}

data "openstack_images_image_v2" "image_id" {
  for_each    = { for k, v in local.instances : v.name => v }
  name        = each.value.image_name
}

#security group
resource "openstack_compute_secgroup_v2" "secgroup" {
 name = "terraform_security_group"
 description = "Created by test terraform security group"

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
