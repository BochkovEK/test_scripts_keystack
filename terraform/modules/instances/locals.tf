locals {
  # flatten ensures that this local value is a flat list of objects, rather
  # than a list of lists of objects.
  instances = flatten([
    for instance_key, instance in var.VMs : [
      for iter in range(1, try(instance.vm_qty, 1) + 1) : {
        base_name                         = instance_key
        name                              = instance.vm_qty == 1 ? instance_key : format("%s-%02d", instance_key, iter)
        image_name                        = try(instance.image_name, var.default_image_name)
        metadata                          = try(instance.metadata, var.default_metadata)
        flavor_name                       = try(instance.flavor_name, var.default_flavor_name)
        keypair_name                      = try(instance.keypair_name, null) #var.default_key_pair_name)
        security_groups                   = try(instance.security_groups, null) #var.default_security_groups)
        server_group_uuid                 = try(instance.server_group_uuid, null)
        server_group                      = try(instance.server_group, null)
        az_hint                           = try(instance.az_hint, null)
        config_drive                      = try(instance.config_drive, null)
        scheduler_hints                   = try(instance.scheduler_hints, null)
        network_name                      = try(instance.network_name, var.default_network_name)
        boot_volume_size                  = try(instance.boot_volume_size, var.default_volume_size)
        boot_volume_delete_on_termination = try(instance.boot_volume_delete_on_termination, var.default_delete_on_termination)
        disks                             = try(instance.disks, var.default_disks)
    #    user_data                         = try(instance.user_data, var.default_user_data)
        user_data = try(
          templatefile(
              instance.user_data.template_file,
              try(instance.user_data.vars, {})  # If vars is not provided, pass an empty object.
            ),
            # else use string or default empty string
            instance.user_data, var.default_user_data)
        server_group_type = try(
          lookup(instance, "server_group", null) != null ? "new" :
          lookup(instance, "server_group_uuid", null) != null ? "existing" :
          null,
          null
        )
#        server_group_type = try(instance.server_group != null ? "new" : instance.server_group_uuid != null ? "existing" : null, null)
#        server_group_policy = try(instance.server_group.policy, null)
      }
    ]
  ])

    groups_to_create = {
    for vm_key, vm in var.VMs : vm_key => vm.server_group
    if try(vm.server_group, null) != null
  }

  all_data_volumes = flatten([
    for instance in local.instances : [
      for disk_index, disk in try(instance.disks, []) : {
        vm_name               = instance.name
        name                  = format("%s-disk-%02d", instance.name, disk_index + 1)
        size                  = disk.size
        boot_index            = try(disk.boot_index, -1)
        delete_on_termination = try(disk.delete_on_termination, var.default_delete_on_termination)
      }
    ]
  ])
}




