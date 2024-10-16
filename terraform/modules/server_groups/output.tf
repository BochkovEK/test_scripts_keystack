output "server_group_id" {
#  for_each = var.server_groups
  value = openstack_compute_servergroup_v2.servergroup.id
}
