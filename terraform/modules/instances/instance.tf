# Создаем загрузочные тома
resource "openstack_blockstorage_volume_v3" "boot_volume" {
  for_each = local.instances_map

  name              = "${each.key}-boot"
  size              = each.value.boot_volume_size
  image_id          = data.openstack_images_image_v2.image_id[each.key].id
  volume_type       = try(each.value.boot_volume_type, null)
  availability_zone = try(each.value.az_hint, null)
}

# Создаем инстансы без block_device
resource "openstack_compute_instance_v2" "vm" {
  for_each = local.instances_map

  name            = each.value.name
  flavor_name     = each.value.flavor_name == "" ? "${each.value.base_name}-flavor" : each.value.flavor_name
  key_pair        = each.value.keypair_name == null ? openstack_compute_keypair_v2.keypair.name : each.value.keypair_name
  security_groups = each.value.security_groups == null ? [openstack_compute_secgroup_v2.secgroup.name] : each.value.security_groups
  metadata        = each.value.metadata
  user_data       = each.value.user_data

  network {
    name = each.value.network_name
  }

  depends_on = [openstack_compute_flavor_v2.flavor]
}

# Подключаем загрузочные тома
resource "openstack_compute_volume_attach_v2" "boot_attach" {
  for_each = local.instances_map

  instance_id = openstack_compute_instance_v2.vm[each.key].id
  volume_id   = openstack_blockstorage_volume_v3.boot_volume[each.key].id
  device      = "/dev/vda" # Загрузочный диск всегда будет /dev/vda
}

# Создаем дополнительные тома
resource "openstack_blockstorage_volume_v3" "additional_volume" {
  for_each = { for disk in local.disk_attachments : disk.unique_key => disk }

  name              = each.key
  size              = try(each.value.disk_config.size, var.default_volume_size)
  volume_type       = try(each.value.disk_config.volume_type, null)
  availability_zone = try(each.value.disk_config.az, null)
  metadata          = try(each.value.disk_config.metadata, null)
}

# Прикрепляем тома к инстансам
resource "openstack_compute_volume_attach_v2" "volume_attachment" {
  for_each = openstack_blockstorage_volume_v3.additional_volume

  instance_id = openstack_compute_instance_v2.vm[each.value.vm_name].id
  volume_id   = each.value.id
  device      = try(each.value.disk_config.device_name,
                  "/dev/vd${chr(98 + index([for d in local.disk_attachments : d.unique_key], each.key))}")
}

# Получаем ID образа
data "openstack_images_image_v2" "image_id" {
  for_each = local.instances_map
  name     = each.value.image_name
  most_recent = true
}

# Создаем flavor, если нужно
resource "openstack_compute_flavor_v2" "flavor" {
  for_each = { for k, v in var.VMs : k => v if try(v.create_flavor, false) }

  name        = "${each.key}-flavor"
  vcpus       = try(each.value.flavor.vcpus, var.default_flavor.vcpus)
  ram         = try(each.value.flavor.ram, var.default_flavor.ram)
  disk        = 0
  is_public   = true
  extra_specs = try(each.value.flavor.extra_specs, var.default_flavor.extra_specs)
}

# Security group
resource "openstack_compute_secgroup_v2" "secgroup" {
  name        = "terraform_security_group"
  description = "Created by terraform"

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