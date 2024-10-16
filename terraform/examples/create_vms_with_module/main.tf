module "server_groups" {
    source          = "../../modules/server_groups"
    server_groups   = var.server_groups
}

module "VMs" {
    source = "../../modules/instances"
    VMs    = var.VMs
}

module "AZs" {
    source = "../../modules/aggregate"
    AZs    = var.AZs
}
