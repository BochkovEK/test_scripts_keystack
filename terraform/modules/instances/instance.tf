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

## Attach additional volumes
#resource "openstack_compute_volume_attach_v2" "volume_attachment" {
#  for_each = openstack_blockstorage_volume_v3.additional_volume
#
#  instance_id = openstack_compute_instance_v2.vm[local.volume_attachments[each.key].vm_name].id
#  volume_id   = each.value.id
## Безопасное определение устройства с явным приведением к map
#device      = "/dev/vd${element(["b", "c", "d", "e", "f", "g"], index(keys(openstack_blockstorage_volume_v3.additional_volume), each.key))}"
#}

## Подключение дополнительных томов
#resource "openstack_compute_volume_attach_v2" "volume_attachment" {
#  for_each = openstack_blockstorage_volume_v3.additional_volume
#
#  instance_id = openstack_compute_instance_v2.vm[each.value.vm_name].id
#  volume_id   = each.value.id
#  device      = try(each.value.disk_config.device_name,
#                  "/dev/vd${chr(98 + index([for d in local.disk_attachments : d.unique_key], each.key))}")
#}

resource "openstack_compute_volume_attach_v2" "volume_attachment" {
  for_each = openstack_blockstorage_volume_v3.additional_volume

  instance_id = openstack_compute_instance_v2.vm[local.volume_attachments[each.key].vm_name].id
  volume_id   = each.value.id

  # Если device указан в disk_config - используем его с префиксом /dev/, иначе /dev/vdb, /dev/vdc и т.д.
  device = try(
    "/dev/${each.value.disk_config.device}",
    "/dev/vd${element(["b", "c", "d", "e", "f", "g"], index(keys(openstack_blockstorage_volume_v3.additional_volume), each.key))}"
  )
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