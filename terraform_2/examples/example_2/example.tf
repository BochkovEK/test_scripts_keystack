module "aggr_1" {
    source          = "../../modules/aggregate"
    name_aggr   = var.name_aggr
    name_az     = var.name_az
    hosts_list  = var.hosts_list
}