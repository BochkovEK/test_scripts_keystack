terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.52"
    }
  }
}

provider "openstack" {
}

data "openstack_images_image_v2" "ubuntu" {
  name = "ubuntu-20.04-server-cloudimg-amd64.img"
  most_recent = true
}

resource "openstack_compute_aggregate_v2" "az_1" {
  name = "az_1"
  hosts = [
    "cdm-bl-pca04",
    "ebochkov-ks-sber-comp-03",
  ]
  zone = "az_1"
}

resource "openstack_compute_aggregate_v2" "az_2" {
  name = "az_2"
  hosts = [
    "ebochkov-ks-sber-comp-01",
    "ebochkov-ks-sber-comp-02",
    "ebochkov-ks-sber-comp-04",
    "cdm-bl-pca05",
  ]
  zone = "az_2"
}

resource "openstack_compute_flavor_v2" "vm_1_flavor" {
  name      = "custom-vm-1-flavor"
  vcpus     = 2
  ram       = 4096
  disk      = 0
  is_public = false
}

resource "openstack_compute_keypair_v2" "kp_1" {
  name       = "vm-1-keypair"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "openstack_blockstorage_volume_v2" "boot_volumes" {
  count = 4
  name  = "boot-volume-vm-1-${count.index + 1}"
  size  = 1
  image_id = data.openstack_images_image_v2.ubuntu.id
  volume_type = "your-volume-type"
}

resource "openstack_blockstorage_volume_v2" "data_volumes_1" {
  count = 4
  name  = "data-volume-1-vm-1-${count.index + 1}"
  size  = 2
  volume_type = "your-volume-type"
}

resource "openstack_blockstorage_volume_v2" "data_volumes_2" {
  count = 4
  name  = "data-volume-2-vm-1-${count.index + 1}"
  size  = 3
  volume_type = "your-volume-type"
}

resource "openstack_compute_instance_v2" "vm" {
  count = 4
  name              = "vm_1-${count.index + 1}"
  availability_zone = "az_1"
  key_pair        = openstack_compute_keypair_v2.kp_1.name
  flavor_id       = openstack_compute_flavor_v2.vm_1_flavor.id
  scheduler_hints {
    host = "cdm-bl-pca04"
  }

  network {
    name = "your-network-name"
  }

  block_device {
    uuid                  = openstack_blockstorage_volume_v2.boot_volumes[count.index].id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = false
  }

  depends_on = [
    openstack_compute_aggregate_v2.az_1,
    openstack_compute_aggregate_v2.az_2
  ]
}

resource "openstack_compute_volume_attach_v2" "attach_data_1" {
  count       = 4
  instance_id = openstack_compute_instance_v2.vm[count.index].id
  volume_id   = openstack_blockstorage_volume_v2.data_volumes_1[count.index].id
}

resource "openstack_compute_volume_attach_v2" "attach_data_2" {
  count       = 4
  instance_id = openstack_compute_instance_v2.vm[count.index].id
  volume_id   = openstack_blockstorage_volume_v2.data_volumes_2[count.index].id
}

output "vm_ips" {
  value = { for vm in openstack_compute_instance_v2.vm : vm.name => vm.access_ip_v4 }
}