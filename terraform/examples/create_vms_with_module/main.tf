module "server_group" {
    source          = "../../modules/server_group"
#    for_each = var.server_groups ? var.server_groups : {}
#    name       = each.key
#     policies = each.value.policies
#    for_each = [for group in var.server_groups: {
##            boot_index = volume.boot_index
##            size = volume.size
#      name       = group.name
#     policies = group.policies
#    }]

  server_groups = var.server_groups
}

module "VMs" {
    source = "../../modules/instances"
    VMs    = var.VMs
}

module "AZs" {
    source = "../../modules/aggregate"
    AZs    = var.AZs
}
