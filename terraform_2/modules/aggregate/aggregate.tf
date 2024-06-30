resource "openstack_compute_aggregate_v2" "aggr" {
#  region = "RegionOne"
  name   = var.aggr_name #"aggr_1"
  zone   = var.az_name #"az_1"
  metadata = {
#    cpus = "56"
  }
  hosts = var.hosts_list
}