# VMs
VMs = {
  TEST_DRS = {
#    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    image_name = "test_cirros"
    flavor          = {
        vcpus = 2
        ram   = 2048
    }
    vm_qty          = 3
  }
    TEST_DRS_2 = {
    image_name      = "ubuntu-20.04-server-cloudimg-amd64.img"
    flavor          = {
        vcpus = 2
        ram   = 2048
    }
    keypair_name = "key_test"
    vm_qty          = 3
  }
}

# AZs
AZs = {
 foo = {
    az_name = "foo_az"
    hosts_list = [
      "ebochkov-keystack-comp-01",
      "ebochkov-keystack-comp-01",
    ]
  }
}

server_groups = {}

