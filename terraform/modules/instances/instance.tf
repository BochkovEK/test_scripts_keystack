resource "openstack_compute_instance_v2" "vm" {
  for_each = { for k, v in local.instances : v.name => v }

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

# Локальные переменные для томов
locals {
  volume_pairs = flatten([
    for vm_key, vm_config in local.instances : [
      for disk_idx, disk in try(vm_config.disks, []) : {
        vm_key       = vm_key
        disk_config  = disk
        disk_key     = "${vm_key}-disk-${disk_idx}"
      }
    ]
  ])

  volume_map = { for pair in local.volume_pairs : pair.disk_key => pair }
}

# Создание томов
resource "openstack_blockstorage_volume_v3" "additional_volumes" {
  for_each = local.volume_map

  name              = each.key
  size              = try(each.value.disk_config.size, var.default_volume_size)
  volume_type       = try(each.value.disk_config.volume_type, null)
  availability_zone = try(each.value.disk_config.az, null)
}

# Подключение томов
resource "openstack_compute_volume_attach_v2" "volume_attachments" {
  for_each = openstack_blockstorage_volume_v3.additional_volumes

  instance_id = openstack_compute_instance_v2.vm[local.volume_map[each.key].vm_key].id
  volume_id   = each.value.id
  device      = try(local.volume_map[each.key].disk_config.device_name,
                   "/dev/vd${chr(98 + index(keys(local.volume_map), each.key))}")
}

# Остальные ресурсы
resource "openstack_compute_flavor_v2" "flavor" {
  for_each    = var.VMs

  name        = "${each.key}-flavor"
  vcpus       = try(each.value.flavor.vcpus, var.default_flavor.vcpus)
  ram         = try(each.value.flavor.ram, var.default_flavor.ram)
  disk        = "0"
  is_public   = "true"
  extra_specs = try(each.value.flavor.extra_specs, var.default_flavor.extra_specs)
}

data "openstack_images_image_v2" "image_id" {
  for_each = { for k, v in local.instances : v.name => v }
  name     = each.value.image_name
}

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
    ip_protocol = "udp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
}

resource "openstack_compute_keypair_v2" "keypair" {
  name       = "terraform_keypair"
  public_key = var.default_puplic_key
}