# example
#server_groups = {
#  foo = {
#    policies = ["affinity"]
#  }
#}

resource "openstack_compute_servergroup_v2" "server_groups" {
  for_each = var.server_groups
  name   = each.key
  policies   = each.value.policies
#  name =
#  policies = var.server_group.policies
#  name     = each.key
#  policies = each.value.policies
}