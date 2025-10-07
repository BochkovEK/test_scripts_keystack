module "VMs" {
    source = "../../modules/instances"
    VMs    = var.VMs
}

#module "AZs" {
#    source = "../../../tmp/aggregate"
#    AZs    = var.AZs
#}

#output "server_group_types" {
#  value = module.VMs.server_group_types
#}
