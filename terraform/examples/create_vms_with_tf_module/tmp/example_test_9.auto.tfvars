# VMs
VMs = {
  DRS_TEST_1 = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    flavor          = {
        vcpus = 4
        ram   = 4096
    }
    vm_qty          = 2
    az_hint         = "az_1:ebochkov-ks-sber-comp-01"
  }
  DRS_TEST_3 = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    flavor          = {
        vcpus = 4
        ram   = 4096
    }
    vm_qty          = 2
    az_hint         = "az_1:ebochkov-ks-sber-comp-03"
  }
}

# AZs
AZs = {
  aggr_1 = {
    az_name     = "az_1"
    hosts_list  = [
      "ebochkov-ks-sber-comp-01",
      "ebochkov-ks-sber-comp-02",
      "ebochkov-ks-sber-comp-03",
      "ebochkov-ks-sber-comp-04",
    ]
  }
}