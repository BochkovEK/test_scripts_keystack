resource "openstack_networking_secgroup_v2" "allow_all" {
  name        = "allow_all"
  description = "Open all traffic"
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_rule_1" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_all.id
}