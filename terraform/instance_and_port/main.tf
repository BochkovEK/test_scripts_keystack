#keypair
resource "openstack_compute_keypair_v2" "test-keypair" {
 name = var.keypair.name
 public_key = var.keypair.public_key
}

#flavor
resource "openstack_compute_flavor_v2" "flavor" {
  flavor_id = var.flavor.name
  name      = var.flavor.name
  vcpus     = var.flavor.vcpus
  ram       = var.flavor.ram
  disk      = var.flavor.disk
  is_public = var.flavor.id_public
}

#security group
resource "openstack_compute_secgroup_v2" "secgroup" {
 name = "terraform_security_group"
 description = "Created by test terraform security group"
 rule {
  from_port = 22
  to_port = 22
  ip_protocol = "tcp"
  cidr = "0.0.0.0/0"
 }
 rule {
  from_port = -1
  to_port = -1
  ip_protocol = "icmp"
  cidr = "0.0.0.0/0"
 }
}

# Create network port
resource "openstack_networking_port_v2" "port" {
 count = var.qty
 name                   = "test-port-${count.index}"
 network_id             = data.openstack_networking_network_v2.network.id
 fixed_ip {
  subnet_id = "${data.openstack_networking_subnet_v2.subnet.id}"
  ip_address = "${var.fixed_ip_pattren}${count.index}"
 }
 admin_state_up = true
 security_group_ids = [
 openstack_compute_secgroup_v2.secgroup.id
 ]
}

#
#resource "openstack_networking_port_v2" "port_1" {
# count = var.qty
# name = "port_1"
# admin_state_up = "true"
# network_id = "0a1d0a27-cffa-4de3-92c5-9d3fd3f2e74d"
# security_group_ids = [
# "2f02d20a-8dca-49b7-b26f-b6ce9fddaf4f",
# "ca1e5ed7-dae8-4605-987b-fadaeeb30461",
# ]
#}

#Instance
resource "openstack_compute_instance_v2" "instance_1" {
 count                       = var.qty
 name                        = "${var.vm_name}-${count.index}"
 key_pair                    = openstack_compute_keypair_v2.test-keypair.id
 flavor_name                 = openstack_compute_flavor_v2.flavor.name
 security_groups             = [
  openstack_compute_secgroup_v2.secgroup.name
 ]
 availability_zone_hints     = var.az_hint
 metadata = {
  test_meta = "Created by Terraform"
 }
 network {
  port = openstack_networking_port_v2.port[count.index].id
 }
}

#resource "openstack_networking_port_v2" "port_1" {
# name = "port_1"
# network_id = "${openstack_networking_network_v2.network_1.id}"
# admin_state_up = "true"
# security_group_ids = ["${openstack_compute_secgroup_v2.secgroup_1.id}"]
# fixed_ip {
# "subnet_id" = "${openstack_networking_subnet_v2.subnet_1.id}"
# "ip_address" = "192.168.199.10"
# }
#}