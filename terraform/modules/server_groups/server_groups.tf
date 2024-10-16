#resource "openstack_compute_aggregate_v2" "aggr" {
#  for_each = var.AZs
#  name   = each.key
#  zone   = each.value.az_name #"az_1"
#  metadata = {
##    cpus = "56"
#  }
#  hosts = each.value.hosts_list
#}

resource "openstack_compute_servergroup_v2" "servergroup" {
#  for_each = var.server_groups
  name     = var.server_group_name
  policies = var.server_group_policies
}