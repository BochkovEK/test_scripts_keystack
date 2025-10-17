resource "openstack_compute_aggregate_v2" "aggr" {
  for_each = var.AZs
  name   = each.key
  zone   = each.value.az_name #"az_1"
  metadata = {
    test_meta = "Created by Terraform AZ_module"
  }
  hosts = each.value.hosts_list
}