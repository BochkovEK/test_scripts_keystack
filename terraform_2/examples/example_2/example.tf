module "vm_in_az_1" {
    source          = "../../modules/instances"
    vm_name         = var.vm_name_1
    image_name      = var.image_name
    keypair_name    = var.keypair_name
    network_name    = var.network_name
    flavor_name     = var.flavor_name
    security_groups = var.security_groups
    vm_qty          = var.vms_count_1
    az_hints        = var.name_az_1
#    depends_on      = [module.aggr_1]
}

module "vm_in_az_2" {
    source          = "../../modules/instances"
    vm_name         = var.vm_name_2
    image_name      = var.image_name
    keypair_name    = var.keypair_name
    network_name    = var.network_name
    flavor_name     = var.flavor_name
    security_groups = var.security_groups
    vm_qty          = var.vms_count_2
    az_hints        = var.name_az_2
#    depends_on      = [module.aggr_2]
}

module "aggr_1" {
    source          = "../../modules/aggregate"
    name_aggr   = var.name_aggr_1
    name_az     = var.name_az_1
    hosts_list  = var.hosts_list_1
}

module "aggr_2" {
    source          = "../../modules/aggregate"
    name_aggr   = var.name_aggr_2
    name_az     = var.name_az_2
    hosts_list  = var.hosts_list
}