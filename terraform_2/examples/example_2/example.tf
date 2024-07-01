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

#module "VMs" {
#    source = "../../modules/instances"
##    count = 2
#    VMs = var.VMs
#}

module "VMs" {
    source = "../../modules/instances"
    for_each = var.VMs # == {} ? null : var.VMs
  vm_name                        = format("%s-%02d", each.value.vm_name) #, count.index+1)
  image_name                  = each.value.image_name == null ? var.default_image_name : each.value.image_name
  volume_size                 = each.value.volume_size == null ? var.default_volume_size : each.value.volume_size
  flavor_name                 = each.value.flavor_name == null ? var.default_flavor_name : each.value.flavor_name
  keypair_name                    = each.value.keypair_name
  security_groups             = each.value.security_groups
  availability_zone_hints     = each.value.az_hint

  #  metadata = {
#    this = "that"
#  }
#  block_device {
#    uuid                  = each.value.image_name == null ? var.default_image_name : each.value.image_name
#    source_type           = "image"
#    volume_size           = each.value.volume_size == null ? var.default_volume_size : each.value.volume_size
#    boot_index            = 0
##    destination_type      = "volume"
#    delete_on_termination = true
#  }
    network_name = each.value.network_name == null ? var.default_network_name : each.value.network_name
}

#module "AZs" {
#    source          = "../../modules/aggregate"
#    AZs = var.AZs
##  region = "RegionOne"
#}

#module "aggr_2" {
#    source          = "../../modules/aggregate"
#    aggr_name   = var.aggr_name_2
#    az_name     = var.az_name_2
#    hosts_list  = var.hosts_list_2
#}