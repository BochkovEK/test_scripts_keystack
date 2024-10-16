output "server_group_id" {
#  for_each = var.server_groups
#  value = openstack_compute_servergroup_v2.server_groups[*].id
  value = {for k, value in openstack_compute_servergroup_v2.server_groups: k => value.id}
}
