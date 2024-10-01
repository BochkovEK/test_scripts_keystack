# Server group (affinity)
server_group = {
  name      = "terraform_affinity_sg"
  policies = [
      "affinity"
  ]
}

image_name = "cirros-0.6.2-x86_64-disk.img"

# Server group (anti-affinity)
#server_group = {
#  name      = "terraform_anti-affinity_sg"
#  policies = [
#      "anti-affinity"
#  ]
#}
