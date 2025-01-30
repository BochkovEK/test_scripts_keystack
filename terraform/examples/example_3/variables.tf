variable "qty" {
  description = "quantity of VMs"
  default     = 4
}

variable "vm_name" {
  description = "VM name"
  default = "TEST_VM"
}

variable "keypair" {
  description = "Please define keypair name if team need to be overrided"
  default     = {
    name        = "terraform_key_test"
    public_key  = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+hfe70miomf6AwSIfZ4IDZZZqm+uUJd4hqunlqzkxfeznw30kvwX8MOdFwM982EuaUeO373Wcj2dD2fg2Pfy2KoQtRw0hKAdV6xMj6ZXwJ1jd7ISSlPNZlf3oKdeZhYHoj7/1gdhMahZVbFWAfI1ndT99kNmXkElxHg462RftdfAaapfc7IuE7mTrSG/c8q0EBdRQ7QhE+6KWpRxcE4ybfcEgTYKIY6Kc9HVqx21mTxScaz6XfHs8k+/dtaW2XHdmhCsh8lmdExPSpTXQpieQHzqg0n1aK7/qstzNdW0KiH2fSXvMFMfRKibp7LEZkvP7Lqgre398ItCjgfbj8bN/ Generated-by-Nova"
  }
}

variable "image_name" {
  description = "Please image name"
  default     = "cirros-0.6.2-x86_64-disk"
}

variable "volume_size" {
  description = "Volume size in GB"
  default = 1
}

variable "flavor_name" {
  default     = "terraform_test_flavor"
}

variable "vcpus" {
  default = 2
}

variable "ram" {
  default = 2048
}

variable "flavor_disk" {
  default = 0
}

#variable "flavor" {
#  description = "Please flavor name"
#  default     = {
#    name        = var.flavor_name
#    vcpus       = var.vcpus
#    ram         = var.ram
#    disk        = var.default_flavor_disk
#    is_public   = "true"
#  }
#}

variable "az_hint" {
  description = "The AZ name if needed. Valid format: '<az_name>' or '<az_name>:<hypervisor_name>'"
  default     = ""
}

variable "network_name" {
  description = "Network name"
  default     = "pub_net"
}

variable "server_group" {
  description = "Server group name"
  default     = {
    name      = "terraform_affinity_sg"
    policies = [
      "affinity"
    ]
  }
}

variable "AZs" {
  description = "AZs list source"
  default = {}
}
