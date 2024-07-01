locals {
  # flatten ensures that this local value is a flat list of objects, rather
  # than a list of lists of objects.
  instances = flatten([
    for instance_key, instance in var.VMs : [
      for iter in range(1,instance.vm_qty+1) : {
        flavor           = instance.flavor_name
#        tags             = instance.tags
        name             = format("%s-%02d", instance_key, iter)
      }
    ]
  ])
}
