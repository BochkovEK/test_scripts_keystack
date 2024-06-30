# VM
image_name      = "ubuntu-20.04-server-cloudimg-amd64"
flavor_name     = "4c-2r"
network_name    = "pub_net"
security_groups = ["test_security_group"]
keypair_name    = "key_test"
#vm_qty          = "2"

# First AZ
aggr_name_1   = "aggr_1"
az_name_1     = "az_1"
hosts_list_1  = [
  "ebochkov-ks-sber-comp-01",
  "ebochkov-ks-sber-comp-02",
]
vms_count_1   = "2"
vm_name_1     = "VM_1"

# Second AZ
aggr_name_2   = "aggr_2"
az_name_2     = "az_2"
hosts_list_2  = [
  "ebochkov-ks-sber-comp-03",
  "ebochkov-ks-sber-comp-04",
]
vms_count_2   = "0"
vm_name_2     = "VM_2"