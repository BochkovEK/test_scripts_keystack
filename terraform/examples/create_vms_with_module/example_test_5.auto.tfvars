# VMs
VMs = {
  DRS_TEST_1 = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    flavor          = {
        vcpus = 2
        ram   = 2048
      }
    vm_qty          = 3
    az_hint         = "az_1:ebochkov-keystack-comp-01"
  }
  DRS_TEST_3 = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    vm_qty          = 3
    az_hint         = "az_2:ebochkov-keystack-comp-03"
  }
  DRS_TEST_4 = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    vm_qty          = 3
    az_hint         = "az_2:ebochkov-keystack-comp-04"
  }
}

# AZs
AZs = {
  aggr_1 = {
    az_name = "az_1"
    hosts_list = [
      "ebochkov-keystack-comp-01",
      "ebochkov-keystack-comp-02",
    ]
  }
  aggr_2 = {
    az_name = "az_2"
    hosts_list = [
      "ebochkov-keystack-comp-03",
      "ebochkov-keystack-comp-04",
    ]
  }
}