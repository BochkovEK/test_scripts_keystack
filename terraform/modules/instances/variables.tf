## VM
variable "default_image_name" {
  description = "Default image name"
  type        = string
  default = "cirros-0.6.2-x86_64-disk"
}

variable "default_flavor_name" {
  description = "Default flavor name"
  type        = string
  default = ""
}

variable "default_flavor" {
#  description = "Default flavor name"
  default = {
    vcpus = 2
    ram   = 2048
  }
}

variable "default_disks" {
  description = "Default disks"
  default     = []
}

variable "default_boot_volume_size" {
  description = "Default volume size"
  type        = number
  default     = 5
}

variable "default_network_name" {
  description = "Default network name"
  type        = string
  default     = "pub_net"
}

#variable "default_security_groups" {
#  description = "Default security_groups"
#  type        = list(string)
##  default = ["test_security_group"]
#  default     = []
#}

#variable "default_key_pair_name" {
#  description = "Default key pair"
#  type        = string
#  default     = ""
#}

variable "default_puplic_key" {
  description = "Default puplic key"
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCTEPRSGFkfN32OwUUjLCi7zsSeQJyToYVhfd4ft2SSmu9RefWgtwVL5yrglL474vTl6/q+I8ZLtCJdeIXJ2y7q6sf20Vf5vwLINNsMetC970Z3YXCTQR3ydrYjvp6U4PhNUt/eGe9IGNOvrdUdIj/8ur0carZDEP1PkKwgJF24LGYv13cXjnhiNU7cAVQj/7n0b2uoyykYrBq1kN+fVHRpDyvyswzLPqNuIyVh2YqdYerunue9WU6GBbVpiD0zvXA6yGd6znkHVu8aGfTXa9Ui8PsOVlH8km8YylVB8Egsjvl63cSx7zeYC+GeXgOS9B5EmTpf/i09sPlfPKRsVv6F Generated-by-Nova"
}

variable "default_az_hints" {
  description = "Default availability zone hints"
  type        = string
  default     = ""
}

#variable "VMs" {
#  description = "VMs list source"
#  default = {}
#}

#variable "AZs" {
#  description = "AZs list source"
#  default = {}
#}
