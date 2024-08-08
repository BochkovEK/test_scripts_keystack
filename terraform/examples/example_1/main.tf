module "VMs" {
    source = "../../modules/instances"
    VMs    = var.VMs
}

module "AZs" {
    source = "../../modules/aggregate"
    AZs    = var.AZs
#  region = "RegionOne"
}

output "foo" {
  value = local.instances
}
