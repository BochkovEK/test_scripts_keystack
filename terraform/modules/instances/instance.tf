locals {
  instances = flatten([
    for instance_key, instance in var.VMs : [
      for iter in range(1, instance.vm_qty+1) : {
        base_name                         = instance_key
        name                              = format("%s-%02d", instance_key, iter)
        image_name                        = try(instance.image_name, var.default_image_name)
        metadata                          = try(instance.metadata, var.default_metadata)
        flavor_name                       = try(instance.flavor_name, var.default_flavor_name)
        keypair_name                      = try(instance.keypair_name, null)
        security_groups                   = try(instance.security_groups, null)
        az_hint                           = try(instance.az_hint, null)
        network_name                      = try(instance.network_name, var.default_network_name)
        boot_volume_size                  = try(instance.boot_volume_size, var.default_volume_size)
        boot_volume_delete_on_termination = try(instance.boot_volume_delete_on_termination, var.default_delete_on_termination)
        disks                             = try(instance.disks, var.default_disks)
        user_data                         = try(instance.user_data, var.default_user_data)
      }
    ]
  ])

  instances_map = { for instance in local.instances : instance.name => instance }

  disk_attachments = flatten([
    for vm_name, vm_config in local.instances_map : [
      for disk_idx, disk in try(vm_config.disks, []) : {
        vm_name     = vm_name
        disk_config = disk
        unique_key  = "${vm_name}-disk-${disk_idx}"
      }
    ]
  ])

  volume_attachments = { for disk in local.disk_attachments : disk.unique_key => {
    vm_name     = disk.vm_name
    size        = try(disk.disk_config.size, var.default_volume_size)
    volume_type = try(disk.disk_config.volume_type, null)
    az          = try(disk.disk_config.az, null)
    device_name = try(disk.disk_config.device, null)
  }}
}

# Instances
resource "openstack_compute_instance_v2" "vm" {
  for_each = local.instances_map

  name                    = each.value.name
  image_name              = each.value.image_name
  flavor_name             = each.value.flavor_name == "" ? "${each.value.base_name}-flavor" : each.value.flavor_name
  key_pair                = each.value.keypair_name == null ? openstack_compute_keypair_v2.keypair.name : each.value.keypair_name
  security_groups         = each.value.security_groups == null ? [openstack_compute_secgroup_v2.secgroup.name] : each.value.security_groups
  availability_zone_hints = each.value.az_hint
  metadata                = each.value.metadata
  user_data               = each.value.user_data

  block_device {
    uuid                  = data.openstack_images_image_v2.image_id[each.key].id
    volume_size           = each.value.boot_volume_size
    source_type           = "image"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = each.value.boot_volume_delete_on_termination
  }

  network {
    name = each.value.network_name
  }

  depends_on = [openstack_compute_flavor_v2.flavor]
}

# Additional volumes
resource "openstack_blockstorage_volume_v3" "additional_volume" {
  for_each = local.volume_attachments

  name              = each.key
  size              = each.value.size
  volume_type       = each.value.volume_type
  availability_zone = each.value.az
}

# Attach additional volumes
resource "openstack_compute_volume_attach_v2" "volume_attachment" {
  for_each = openstack_blockstorage_volume_v3.additional_volume

  instance_id = openstack_compute_instance_v2.vm[local.volume_attachments[each.key].vm_name].id
  volume_id   = each.value.id
  device      = try(local.volume_attachments[each.key].device_name,
                  "/dev/${chr(98 + index(keys(local.volume_attachments), each.key))}")
}

# Flavor
resource "openstack_compute_flavor_v2" "flavor" {
  for_each = var.VMs

  name        = "${each.key}-flavor"
  vcpus       = try(each.value.flavor.vcpus, var.default_flavor.vcpus)
  ram         = try(each.value.flavor.ram, var.default_flavor.ram)
  disk        = "0"
  is_public   = "true"
  extra_specs = try(each.value.flavor.extra_specs, var.default_flavor.extra_specs)
}

# Data source for images
data "openstack_images_image_v2" "image_id" {
  for_each = local.instances_map
  name     = each.value.image_name
  most_recent = true
}

# Security group
resource "openstack_compute_secgroup_v2" "secgroup" {
  name        = "terraform_security_group"
  description = "Created by test terraform security group"

  rule {
    from_port   = -1
    to_port     = -1
    ip_protocol = "icmp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "udp"
    cidr        = "0.0.0.0/0"
  }
}

# Key pair
resource "openstack_compute_keypair_v2" "keypair" {
  name       = "terraform_keypair"
  public_key = var.default_puplic_key
}