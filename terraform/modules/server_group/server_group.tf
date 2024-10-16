#resource "openstack_compute_aggregate_v2" "aggr" {
#  for_each = var.AZs
#  name   = each.key
#  zone   = each.value.az_name #"az_1"
#  metadata = {
##    cpus = "56"
#  }
#  hosts = each.value.hosts_list
#}

#server_groups = {
#  foo = {
#    policies = ["affinity"]
#  }
#}

resource "openstack_compute_servergroup_v2" "server_group" {
#  for_each = var.server_groups
  name = var.server_group.name
  policies = var.server_group.policies
#  name     = each.key
#  policies = each.value.policies
}