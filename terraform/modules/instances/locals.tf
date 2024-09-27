locals {
  # flatten ensures that this local value is a flat list of objects, rather
  # than a list of lists of objects.
  instances = flatten([
  for instance_key, instance in var.VMs : [
  for iter in range(1, instance.vm_qty+1) : {
    base_name        = instance_key
    name             = format("%s-%02d", instance_key, iter)
    image_name       = try(instance.image_name, var.default_image_name)
    #        flavor            = try(instance.flavor, var.default_flavor)
    flavor_name       = try(instance.flavor_name, var.default_flavor_name)
    keypair_name     = try(instance.keypair_name, null) #var.default_key_pair_name)
    security_groups  = try(instance.security_groups, toset([])) #var.default_security_groups)
    az_hint          = try(instance.az_hint, null)
    #        volume_size       = try(instance.volume_size, var.default_volume_size)
    network_name     = try(instance.network_name, var.default_network_name)
    boot_volume_size = try(instance.boot_volume_size, var.default_boot_volume_size)
    disks            = try(instance.disks, var.default_disks)
  }
  ]
  ])
#  volume = flatten([

#  ])
}

#locals {
#
#}
#  disks = flatten([
#    for instance_key, instance in var.VMs : {
#      name                = "${instance_key}-flavor"
#    }
#  ])
#}
