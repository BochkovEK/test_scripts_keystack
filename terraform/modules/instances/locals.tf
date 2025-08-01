locals {
  # flatten ensures that this local value is a flat list of objects, rather
  # than a list of lists of objects.
  instances = flatten([
    for instance_key, instance in var.VMs : [
      for iter in range(1, instance.vm_qty+1) : {
        base_name                         = instance_key
        name                              = format("%s-%02d", instance_key, iter)
        image_name                        = try(instance.image_name, var.default_image_name)
        metadata                          = try(instance.metadata, var.default_metadata)
        flavor_name                       = try(instance.flavor_name, var.default_flavor_name)
        keypair_name                      = try(instance.keypair_name, null) #var.default_key_pair_name)
        security_groups                   = try(instance.security_groups, null) #var.default_security_groups)
        server_group                      = try(instance.server_group, null)
        az_hint                           = try(instance.az_hint, null)
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
        # Определяем тип группы (null | existing | new)
        server_group_type = try(instance.server_group_name != null ? "existing" : "new", null)
        # Параметры группы
        server_group_name  = try(instance.server_group.name, instance.server_group_name, null)
        server_group_policy = try(instance.server_group.policy, null)
      }
    ]
  ])
#    # Вычисляем какие server groups нужно создать
#  server_groups = {
#    for vm_key, vm in var.VMs : vm_key => vm.server_group
#    if try(vm.server_group, null) != null
#  }

    # Группы для создания (только с group_type = "new")
    groups_to_create = {
    for vm_key, vm in var.VMs : vm_key => vm.server_group
    if try(vm.server_group, null) != null
  }
}

