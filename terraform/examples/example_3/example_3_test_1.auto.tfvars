# Server group (affinity)
server_group = {
  name      = "terraform_affinity_sg"
  policies = [
      "affinity"
  ]
}

# Server group (anti-affinity)
#server_group = {
#  name      = "terraform_anti-affinity_sg"
#  policies = [
#      "anti-affinity"
#  ]
#}
