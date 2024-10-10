# Images name
image_name = "cirros-0.6.2-x86_64-disk.img"

# ===================
# Server group (affinity)
# VMs quantity
qty = 4

#server_group = {
#  name      = "terraform_affinity_sg"
#  policies = [
#      "affinity"
#  ]
#}

#az_hint = nova:

# ===================
# Server group (anti-affinity)
# VMs quantity
#qty = <hypervisors_count>

server_group = {
  name      = "terraform_anti-affinity_sg"
  policies = [
      "anti-affinity"
  ]
}
