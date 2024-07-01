#module "vm_in_az_1" {
#    source          = "../../modules/instances"
#    vm_name         = var.vm_name_1
#    image_name      = var.image_name
#    keypair_name    = var.keypair_name
#    network_name    = var.network_name
#    flavor_name     = var.flavor_name
#    security_groups = var.security_groups
#    az_hints        = var.az_name_1
#    vm_qty          = var.vms_count_1
#    volume_size     = var.volume_size
#    #    count           = var.vms_count_1
#    #    depends_on      = [module.aggr_1]
#}
#
#module "vm_in_az_2" {
#    source          = "../../modules/instances"
#    vm_name         = var.vm_name_2
#    image_name      = var.image_name
#    keypair_name    = var.keypair_name
#    network_name    = var.network_name
#    flavor_name     = var.flavor_name
#    security_groups = var.security_groups
#    az_hints        = var.az_name_2
#    vm_qty          = var.vms_count_2
#    volume_size     = var.volume_size
#    #    count           = var.vms_count_2
#    #    depends_on      = [module.aggr_2]
#}

module "VMs" {
    source = "../../modules/instances"
    VMs = var.VMs
}

module "AZs" {
    source          = "../../modules/aggregate"
    AZs = var.AZs
#  region = "RegionOne"
}

#module "aggr_2" {
#    source          = "../../modules/aggregate"
#    aggr_name   = var.aggr_name_2
#    az_name     = var.az_name_2
#    hosts_list  = var.hosts_list_2
#}