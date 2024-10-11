# VMs
VMs = {
  DRS_TEST_1 = {
    image_name      = "jammy-server-cloudimg-amd64.img"
    flavor          = {
        vcpus = 4
        ram   = 4096
      }
    vm_qty          = 2
#    az_hint         = "az_1:ebochkov-ks-sber-comp-01"
  }
#  DRS_TEST_2 = {
#    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
#    vm_qty          = 2
#    az_hint         = "az_1:ebochkov-ks-sber-comp-02"
##    flavor_name     = "2c-2r"
#    flavor          = {
#        vcpus = 4
#        ram   = 4096
#      }
#    keypair_name    = "key_test"
#    security_groups = ["test_security_group"]
#  }
}

# AZs
AZs = {
}
#  aggr_1 = {
#    az_name = "az_1"
#    hosts_list = [
#      "ebochkov-ks-sber-comp-01",
#      "ebochkov-ks-sber-comp-02",
#    ]
#  }
#  aggr_2 = {
#    az_name = "az_2"
#    hosts_list = [
#      "ebochkov-ks-sber-comp-03",
#      "ebochkov-ks-sber-comp-04",
#    ]
#  }
#}