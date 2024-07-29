resource "openstack_compute_flavor_v2" "g1-cpu-1-1" {
  flavor_id = "g1-cpu-1-1"
  name      = "g1-cpu-1-1"
  vcpus     = "1"
  ram       = "1024"
  disk      = "0"
  is_public = "true"
}

resource "openstack_compute_instance_v2" "fc_hdd" {
  count = var.qty
  name         = "fc_hdd-vm"
  flavor_name  = "g1-cpu-1-1"
  key_pair     = var.keypair
  availability_zone_hints     = "cpu:cdm-bl-pca10"
  network {
    port = openstack_networking_port_v2.fc_hdd_port[count.index].id
  }
  block_device {
#    uuid                  = openstack_blockstorage_volume_v3.fc_hdd_sda[count.index].id
    uuid                  = data.openstack_images_image_v2.image.id
    volume_size           = 1
    source_type           = "image"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = false
  }

  lifecycle {
    ignore_changes = [user_data, ]
  }
}

# Create network port
resource "openstack_networking_port_v2" "fc_hdd_port" {
  count = var.qty
  name         = "fc_hdd-port"
  network_id         = data.openstack_networking_network_v2.pub_net.id
  admin_state_up     = true
  security_group_ids = [ openstack_networking_secgroup_v2.allow_all.id ]
}

# Create volume
resource "openstack_blockstorage_volume_v3" "fc_hdd_sda" {
  count = var.qty
#  image_id             = data.openstack_images_image_v2.image.id
  name         = "fc_hdd_sda"
  size                 = 1
  enable_online_resize = true
  lifecycle {
    ignore_changes  = [image_id, volume_type]
  }
}

resource "openstack_blockstorage_volume_v3" "fc_hdd_sdb" {
  count = var.qty
  name         = "fc_hdd_sdb"
  size                 = 1
  enable_online_resize = true
  lifecycle {
    ignore_changes  = [image_id, volume_type]
  }
}

resource "openstack_blockstorage_volume_v3" "fc_hdd_sdc" {
  count = var.qty
  name         = "fc_hdd_sdc"
  size                 = 1
  enable_online_resize = true
  lifecycle {
    ignore_changes  = [image_id, volume_type]
  }
}

resource "openstack_blockstorage_volume_v3" "fc_hdd_sdd" {
  count = var.qty
  name         = "fc_hdd_sdd"
  size                 = 1
  enable_online_resize = true
  lifecycle {
    ignore_changes  = [image_id, volume_type]
  }
}

resource "openstack_compute_volume_attach_v2" "fc_hdd_sda" {
  count = var.qty
  instance_id = openstack_compute_instance_v2.fc_hdd[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.fc_hdd_sda[count.index].id
}

resource "openstack_compute_volume_attach_v2" "fc_hdd_sdb" {
  count = var.qty
  instance_id = openstack_compute_instance_v2.fc_hdd[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.fc_hdd_sdb[count.index].id
}

resource "openstack_compute_volume_attach_v2" "fc_hdd_sdc" {
  count = var.qty
  instance_id = openstack_compute_instance_v2.fc_hdd[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.fc_hdd_sdc[count.index].id
}

resource "openstack_compute_volume_attach_v2" "fc_hdd_sdd" {
  count = var.qty
  instance_id = openstack_compute_instance_v2.fc_hdd[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.fc_hdd_sdd[count.index].id
}
