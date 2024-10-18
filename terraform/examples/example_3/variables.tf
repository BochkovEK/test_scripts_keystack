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
    public_key  = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCTEPRSGFkfN32OwUUjLCi7zsSeQJyToYVhfd4ft2SSmu9RefWgtwVL5yrglL474vTl6/q+I8ZLtCJdeIXJ2y7q6sf20Vf5vwLINNsMetC970Z3YXCTQR3ydrYjvp6U4PhNUt/eGe9IGNOvrdUdIj/8ur0carZDEP1PkKwgJF24LGYv13cXjnhiNU7cAVQj/7n0b2uoyykYrBq1kN+fVHRpDyvyswzLPqNuIyVh2YqdYerunue9WU6GBbVpiD0zvXA6yGd6znkHVu8aGfTXa9Ui8PsOVlH8km8YylVB8Egsjvl63cSx7zeYC+GeXgOS9B5EmTpf/i09sPlfPKRsVv6F Generated-by-Nova"
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
