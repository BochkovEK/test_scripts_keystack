locals {
  # flatten ensures that this local value is a flat list of objects, rather
  # than a list of lists of objects.
  instances = flatten([
    for instance_key, instance in var.VMs : [
      for iter in range(1,instance.vm_qty+1) : {
        name              = format("%s-%02d", instance_key, iter)
        image_name        = try(instance.image_name, var.default_image_name) # instance.image_name == null ? var.default_image_name : instance.image_name
        flavor_name       = try(instance.flavor_name, var.default_flavor_name) # == null ? var.default_flavor_name : instance.flavor_name
        keypair_name      = try(instance.keypair_name, null)
        security_groups   = try(instance.security_groups, null)
        az_hint           = try(instance.az_hint, null)
        volume_size       = try(instance.volume_size, var.default_volume_size) # == null ? var.default_volume_size : instance.volume_size
        network_name      = try(instance.network_name, null) # == null ? var.default_network_name : instance.network_name
      }
    ]
  ])
}
