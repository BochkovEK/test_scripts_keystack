resource "openstack_compute_aggregate_v2" "aggr" {
#  region = "RegionOne"
  name   = var.name_aggr #"aggr_1"
  zone   = var.name_az #"az_1"
  metadata = {
#    cpus = "56"
  }
  hosts = var.hosts_list
}