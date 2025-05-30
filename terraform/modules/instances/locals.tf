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
    az_hint                           = try(instance.az_hint, null)
    network_name                      = try(instance.network_name, var.default_network_name)
    boot_volume_size                  = try(instance.boot_volume_size, var.default_volume_size)
    boot_volume_delete_on_termination = try(instance.boot_volume_delete_on_termination, var.default_delete_on_termination)
    disks                             = try(instance.disks, var.default_disks)
#    user_data                         = try(instance.user_data, var.default_user_data)
    user_data = try(
        templatefile(
          instance.user_data.template_file,
          instance.user_data.vars
        ),
        # Иначе используем как есть (если это строка)
        instance.user_data, null)
  }
  ]
  ])
}

