# VMs
VMs = {
}

# AZs
AZs = {
  aggr_1 = {
    az_name     = "az_1"
    hosts_list  = [
      "ebochkov-ks-sber-comp-01",
      "ebochkov-ks-sber-comp-02",
    ]
  }
}

server_groups = {
  anti-affinity-1 = {
    policies = ["anti-affinity"]
  }
  anti-affinity-2 = {
    policies = ["anti-affinity"]
  }
}