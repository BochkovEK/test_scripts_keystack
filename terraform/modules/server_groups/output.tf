output "server_group_id" {
#  for_each = var.server_groups
  value = { for k, servergroup in openstack_compute_servergroup_v2.servergroup.id : k => server_group_id
  }
}
