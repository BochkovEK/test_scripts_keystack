# Images name
image_name = "cirros-0.6.2-x86_64-disk.img"

qty = 4

server_group = {
  name      = "terraform_anti-affinity_sg"
  policies = [
      "anti-affinity"
  ]
}