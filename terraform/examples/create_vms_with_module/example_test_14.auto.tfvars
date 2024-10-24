# VMs
VMs = {
  TEST_DRS = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    flavor          = {
        vcpus = 2
        ram   = 2048
    }
    vm_qty          = 3
#    az_hint         = "az_1:ebochkov-ks-sber-comp-01"
  }
    TEST_DRS_2 = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    flavor          = {
        vcpus = 2
        ram   = 2048
    }
    keypair_name = "key_test"
    vm_qty          = 3
#    az_hint         = "az_1:ebochkov-ks-sber-comp-01"
  }
}

# AZs
AZs = {
}