resource "openstack_compute_instance_v2" "vm" {

  count                       = var.qty

  name                        = format("%s-%02d", var.vm_name, [count.index])
  flavor_name                 = openstack_compute_flavor_v2.flavor.name
  key_pair                    = openstack_compute_keypair_v2.keypair.name
  security_groups             = [
    openstack_compute_secgroup_v2.secgroup.name
  ]
  availability_zone_hints     = var.az_hint
  metadata                    = {
    test_meta             = "Created by Terraform"
  }
  scheduler_hints {
    group                  = openstack_compute_servergroup_v2.servergroup.id
  }
  network {
    name = 	var.network_name
  }
  block_device {
    uuid                  = data.openstack_images_image_v2.image_id.id
    source_type           = "image"
    volume_size           = var.volume_size
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
  block_device {
    source_type = "blank"
    destination_type = "volume"
    boot_index = 1
    volume_size = var.volume_size
    delete_on_termination = true
 }
}

data "openstack_images_image_v2" "image_id" {
  name        = var.image_name
}

resource "openstack_compute_flavor_v2" "flavor" {
  flavor_id = var.flavor.name
  name      = var.flavor.name
  vcpus     = var.flavor.vcpus
  ram       = var.flavor.ram
  disk      = var.flavor.disk
  is_public = var.flavor.is_public
}

resource "openstack_compute_keypair_v2" "keypair" {
  name        = var.keypair.name
  public_key  = var.keypair.public_key
}

resource "openstack_compute_secgroup_v2" "secgroup" {
 name        = "terraform_security_group"
 description = "Created by test terraform security group"
 rule {
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr        = "0.0.0.0/0"
 }
 rule {
  from_port   = -1
  to_port     = -1
  ip_protocol = "icmp"
  cidr        = "0.0.0.0/0"
 }
}

resource "openstack_compute_servergroup_v2" "servergroup" {
  name     = var.server_group.name
  policies = var.server_group.policies
}


