resource "openstack_compute_servergroup_v2" "vm_group" {
  for_each = {
    for vm_key, vm in var.VMs : vm_key => vm.server_group
    if try(vm.server_group, null) != null
  }

  name     = each.value.name
  policies = [each.value.policy]
}

resource "openstack_compute_instance_v2" "vm" {
  for_each     = { for k, v in local.instances : v.name => v
  }
  name                        = each.value.name
  image_name                  = each.value.image_name
  flavor_name                 = each.value.flavor_name == "" ? "${each.value.base_name}-flavor" : each.value.flavor_name
  key_pair                    = each.value.keypair_name == null ? openstack_compute_keypair_v2.keypair.name : each.value.keypair_name
  security_groups             = each.value.security_groups == null ? [openstack_compute_secgroup_v2.secgroup.name] : each.value.security_groups
  availability_zone_hints     = each.value.az_hint
  metadata                    = each.value.metadata
  user_data                   = each.value.user_data
  config_drive                = each.value.config_drive

  dynamic "scheduler_hints" {
    for_each = each.value.server_group_type != null ? [1] : []

    content {
      group = each.value.server_group_type == "new" ? openstack_compute_servergroup_v2.vm_group[each.value.base_name].id : each.value.server_group_uuid
    }
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.image_id[each.key].id
    volume_size           = each.value.boot_volume_size
    source_type           = "image"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = each.value.boot_volume_delete_on_termination
  }

  dynamic block_device {
    for_each = [for volume in each.value.disks: {
        boot_index = try(volume.boot_index, -1)
        size = try(volume.size, var.default_volume_size)
        delete_on_termination = try(volume.delete_on_termination, var.default_delete_on_termination)
    }]
    content {
        source_type           = "blank"
        volume_size           = block_device.value.size
        boot_index            = block_device.value.boot_index
        destination_type      = "volume"
        delete_on_termination = block_device.value.delete_on_termination
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
