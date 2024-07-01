# VMs
VMs = {
  vm_1 = {
    vm_qty          = 1
    image_name      = "ubuntu-20.04-server-cloudimg-amd64"
    az_hint         = "az_2:ebochkov-ks-sber-comp-03"
  }
  vm_2 = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64"
    flavor_name     = "4c-2r"
    network_name    = "pub_net"
    security_groups = ["test_security_group"]
    keypair_name    = "key_test"
    volume_size     = 7
    vm_qty          = 2
    az_hint         = "az_1:ebochkov-ks-sber-comp-01"
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

#image_name      = "ubuntu-20.04-server-cloudimg-amd64"
#flavor_name     = "4c-2r"
#network_name    = "pub_net"
#security_groups = ["test_security_group"]
#keypair_name    = "key_test"
#volume_size     = 7
##vm_qty          = "2"
#

