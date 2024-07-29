resource "openstack_compute_instance_v2" "vm" {
  name                        = test_vm_1
#  image_name                  = cirros-0.5.2-x86_64-disk
  flavor_name                 = g1-cpu-1-1
  key_pair                    = key_test
  security_groups             = allow_all
  availability_zone_hints     = "cpu:cdm-bl-pca11"
  count                       = 5
  metadata = {
    test_meta = "Created by Terraform"
  }
  network {
    name = 	pub_net
  }
  block_device {
    uuid                  = data.openstack_images_image_v2.image_id.id
    source_type           = "image"
    volume_size           = 1
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
  block_device {
    source_type = "blank"
    destination_type = "volume"
    boot_index = 1
    volume_size = 1
    delete_on_termination = true
 }
  block_device {
    source_type = "blank"
    destination_type = "volume"
    boot_index = 2
    volume_size = 1
    delete_on_termination = true
 }
}

data "openstack_images_image_v2" "image_id" {
  name        = cirros-0.5.2-x86_64-disk
}