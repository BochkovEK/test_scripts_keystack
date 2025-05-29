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

  instances_map = {for instance in local.instances : instance.name => instance}

  disk_attachments_map = {
    for idx, attachment in local.disk_attachments :
    attachment.unique_key => {
      vm_name     = attachment.vm_name
      disk_config = try(attachment.disk_config, {})
      unique_key  = attachment.unique_key
    }
  }

  # Список букв для имен устройств
  disk_letters = ["b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m"]

  volume_attachments = {
  for disk in local.disk_attachments : disk.unique_key => {
    vm_name     = disk.vm_name
    size        = try(disk.disk_config.size, var.default_volume_size)
    volume_type = try(disk.disk_config.volume_type, null)
    az          = try(disk.disk_config.az, null)
    device_name = try(disk.disk_config.device, null)
  }
  }

  # Модифицируем disk_attachments, добавляя device_name с префиксом /dev/
  formatted_disk_attachments = {
    for k, v in local.disk_attachments : k => {
      vm_name     = v.vm_name
      disk_config = {
        size        = try(v.disk_config.size, null)
        volume_type = try(v.disk_config.volume_type, null)
        az          = try(v.disk_config.az, null)
        device_name = try("/dev/${v.disk_config.device}", null) # Добавляем префикс здесь
      }
      unique_key  = v.unique_key
    }
  }
}