resource "openstack_images_image_v2" "ubuntu_image" {
  name             = "ubuntu-22.04-server-cloudimg-amd64.img"
#  image_source_url = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
#  local_file_path  = "/root/.terraform/image_cache/1d560741ef4720a143a16bc7db440c7b.img"
  local_file_path  = "/root/images/ubuntu-20.04-server-cloudimg-amd64.img"
  container_format = "bare"
  disk_format      = "qcow2" #raw
  visibility       = "public" #"private" # или "public", "shared", "community"

  min_disk_gb = 5
  min_ram_mb  = 1024
  tags        = ["ubuntu", "22.04", "tf"]

  protected = false

  properties = {
    os_distro    = "ubuntu"
    os_version   = "22.04"
    hw_qemu_guest_agent = "yes"
  }
}