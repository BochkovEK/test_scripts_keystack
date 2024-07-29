resource "openstack_compute_flavor_v2" "g1-cpu-1-1" {
  flavor_id = "g1-cpu-1-1"
  name      = "g1-cpu-1-1"
  vcpus     = "1"
  ram       = "1024"
  disk      = "0"
  is_public = "true"
}

resource "openstack_compute_instance_v2" "fc_hdd" {
  count = 100
  name         = "fc_hdd-itkey"
  flavor_name  = "g1-cpu-1-1"
  key_pair     = var.keypair
  network {
    port = openstack_networking_port_v2.fc_hdd[count.index].id
  }
  block_device {
    uuid                  = openstack_blockstorage_volume_v3.fc_hdd_sda[count.index].id
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = false
  }

  lifecycle {
    ignore_changes = [user_data, ]
  }
}

# Create network port
resource "openstack_networking_port_v2" "fc_hdd" {
  count = 100
  name         = "fc_hdd-itkey"
  network_id         = data.openstack_networking_network_v2.pub_net.id
  admin_state_up     = true
  security_group_ids = [ openstack_networking_secgroup_v2.allow_all.id ]
}

# Create volume
resource "openstack_blockstorage_volume_v3" "fc_hdd_sda" {
  count = 100
  image_id             = data.openstack_images_image_v2.image.id
  name         = "fc_hdd-itkey"
  size                 = 10
  enable_online_resize = true
  lifecycle {
    ignore_changes  = [image_id, volume_type]
  }
}

resource "openstack_blockstorage_volume_v3" "fc_hdd_sdb" {
  count = 100
  name         = "fc_hdd-eboimage"
  size                 = 1
  enable_online_resize = true
  lifecycle {
    ignore_changes  = [image_id, volume_type]
  }
}

resource "openstack_compute_volume_attach_v2" "fc_hdd_sdb" {
  count = 100
  instance_id = openstack_compute_instance_v2.fc_hdd[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.fc_hdd_sdb[count.index].id
}

resource "openstack_blockstorage_volume_v3" "fc_hdd_sdc" {
  count = 100
  name         = "fc_hdd-eboimage"
  size                 = 1
  enable_online_resize = true
  lifecycle {
    ignore_changes  = [image_id, volume_type]
  }
}

resource "openstack_compute_volume_attach_v2" "fc_hdd_sdc" {
  count = 100
  instance_id = openstack_compute_instance_v2.fc_hdd[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.fc_hdd_sdc[count.index].id
}

resource "openstack_blockstorage_volume_v3" "fc_hdd_sdd" {
  count = 100
  name         = "fc_hdd-eboimage"
  size                 = 1
  enable_online_resize = true
  lifecycle {
    ignore_changes  = [image_id, volume_type]
  }
}

resource "openstack_compute_volume_attach_v2" "fc_hdd_sdd" {
  count = 100
  instance_id = openstack_compute_instance_v2.fc_hdd[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.fc_hdd_sdc[count.index].id
}