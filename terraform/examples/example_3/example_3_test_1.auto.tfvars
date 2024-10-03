# Images name
image_name = "cirros-0.6.2-x86_64-disk.img"

# Server group (affinity)
server_group = {
  name      = "terraform_affinity_sg"
  policies = [
      "affinity"
  ]
}

qty = 4

# ===================
# Server group (anti-affinity)

#qty = <hypervisors_count>

#server_group = {
#  name      = "terraform_anti-affinity_sg"
#  policies = [
#      "anti-affinity"
#  ]
#}
