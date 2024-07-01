locals {
  # flatten ensures that this local value is a flat list of objects, rather
  # than a list of lists of objects.
  instances = flatten([
    for instance_key, instance in var.VMs : [
      for iter in range(1,instance.vm_qty+1) : {
        name             = format("%s-%02d", instance_key, iter)
        image_name                  = instance.image_name == null ? var.default_image_name : instance.image_name
        flavor_name                 = instance.flavor_name == null ? var.default_flavor_name : instance.flavor_name
        key_pair                    = instance.value.keypair_name
        security_groups             = instance.value.security_groups
        availability_zone_hints     = instance.value.az_hint
      }
    ]
  ])
}
