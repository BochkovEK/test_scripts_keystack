# VMs
VMs = {
  vm_1 = {
    vm_qty          = 1
    image_name      = "cirros-0.6.2-x86_64-disk"
#    image_name      = "ubuntu-20.04-server-cloudimg-amd64"
    az_hint         = "az_2:ebochkov-ks-sber-comp-03"
    disks = [
      {
        boot_index = 1,
        size = 1
      },
      {
        boot_index = 2,
        size = 2
      },
      {
        boot_index = 3,
        size = 3
      },
    ]
  }
}

# AZs
AZs = {
  aggr_1 = {
    az_name = "az_1"
    hosts_list = [
      "ebochkov-ks-sber-comp-01",
      "ebochkov-ks-sber-comp-02",
    ]
  }
  aggr_2 = {
    az_name    = "az_2"
    hosts_list = [
      "ebochkov-ks-sber-comp-03",
      "ebochkov-ks-sber-comp-04",
    ]
  }
}