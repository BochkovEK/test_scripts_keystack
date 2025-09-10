# VMs
VMs = {
   DRS_TEST = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    flavor          = {
        vcpus = 2
        ram   = 2048
    }
    vm_qty          = 4
    az_hint         = "az_1:ebochkov-ks-sber-comp-01"
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