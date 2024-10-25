#image_name = "cirros-0.6.2-x86_64-disk.img"
image_name = "ubuntu-20.04-server-cloudimg-amd64.img"

# VMs quantity
qty = 4
vcpus = 2
ram = 2048
volume_size = 5

az_hint = "az_1:ebochkov-ks-sber-comp-01"

server_group = {
  name      = "terraform_affinity_sg"
  policies = [
      "affinity"
  ]
}

# AZs
AZs = {
  aggr_1 = {
    az_name = "az_1"
    hosts_list = [
      "ebochkov-ks-sber-comp-01",
      "ebochkov-ks-sber-comp-02",
      "ebochkov-ks-sber-comp-03",
      "ebochkov-ks-sber-comp-04",
    ]
  }
  aggr_2 = {
    az_name = "az_2"
    hosts_list = [
      "cdm-bl-pca04",
      "cdm-bl-pca05",
    ]
  }
}
