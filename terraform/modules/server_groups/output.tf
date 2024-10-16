output "server_group_id" {
  value = openstack_compute_servergroup_v2.servergroup[each.key].id
}
