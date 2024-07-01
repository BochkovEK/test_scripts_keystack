#resource "openstack_compute_aggregate_v2" "aggr" {
##  for_each = var.AZs
##  region = "RegionOne"
#  name   = var.aggr_name
#  zone   = az_name #"az_1"
#  metadata = {
##    cpus = "56"
#  }
#  hosts = hosts_list
#}

resource "openstack_compute_aggregate_v2" "aggr" {
  for_each = var.AZs
  name   = each.key
  zone   = each.value.az_name #"az_1"
  metadata = {
#    cpus = "56"
  }
  hosts = each.value.hosts_list
}