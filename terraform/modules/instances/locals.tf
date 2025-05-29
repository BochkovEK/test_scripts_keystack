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

  disk_attachments = flatten([
  for vm_name, vm_config in local.instances_map : [
  for disk_idx, disk in try(vm_config.disks, []) : {
    vm_name     = vm_name
    disk_config = disk
    unique_key  = "${vm_name}-disk-${disk_idx}"
  }
  ]
  ])

  volume_attachments = {
  for disk in local.disk_attachments : disk.unique_key => {
    vm_name     = disk.vm_name
    size        = try(disk.disk_config.size, var.default_volume_size)
    volume_type = try(disk.disk_config.volume_type, null)
    az          = try(disk.disk_config.az, null)
    device_name = try(disk.disk_config.device, null)
  }
  }
}