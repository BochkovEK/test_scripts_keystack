## VM
variable "default_image_name" {
  description = "Default image name"
  type        = string
  default = "cirros-0.6.2-x86_64-disk.img"
}

variable "default_flavor_name" {
  description = "Default flavor name"
  type        = string
  default = ""
}

variable "default_flavor" {
  #  description = "Default flavor name"
  default = {
    vcpus       = 2
    ram         = 2048
    extra_specs = {
    }
  }
}
#    "hw:mem_page_size" = "large"

variable "default_disks" {
  description = "Default disks"
  default     = []
}

variable "default_volume_size" {
  description = "Default volume size"
  type        = number
  default     = 5
}

variable "default_network_name" {
  description = "Default network name"
  type        = string
  default     = "pub_net"
}

variable "default_delete_on_termination" {
  description = "Default delete on termination"
  type        = string
  default     = "true"
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
#  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCTEPRSGFkfN32OwUUjLCi7zsSeQJyToYVhfd4ft2SSmu9RefWgtwVL5yrglL474vTl6/q+I8ZLtCJdeIXJ2y7q6sf20Vf5vwLINNsMetC970Z3YXCTQR3ydrYjvp6U4PhNUt/eGe9IGNOvrdUdIj/8ur0carZDEP1PkKwgJF24LGYv13cXjnhiNU7cAVQj/7n0b2uoyykYrBq1kN+fVHRpDyvyswzLPqNuIyVh2YqdYerunue9WU6GBbVpiD0zvXA6yGd6znkHVu8aGfTXa9Ui8PsOVlH8km8YylVB8Egsjvl63cSx7zeYC+GeXgOS9B5EmTpf/i09sPlfPKRsVv6F Generated-by-Nova"
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+hfe70miomf6AwSIfZ4IDZZZqm+uUJd4hqunlqzkxfeznw30kvwX8MOdFwM982EuaUeO373Wcj2dD2fg2Pfy2KoQtRw0hKAdV6xMj6ZXwJ1jd7ISSlPNZlf3oKdeZhYHoj7/1gdhMahZVbFWAfI1ndT99kNmXkElxHg462RftdfAaapfc7IuE7mTrSG/c8q0EBdRQ7QhE+6KWpRxcE4ybfcEgTYKIY6Kc9HVqx21mTxScaz6XfHs8k+/dtaW2XHdmhCsh8lmdExPSpTXQpieQHzqg0n1aK7/qstzNdW0KiH2fSXvMFMfRKibp7LEZkvP7Lqgre398ItCjgfbj8bN/ Generated-by-Nova"
}

variable "default_az_hints" {
  description = "Default availability zone hints"
  type        = string
  default     = ""
}

variable "default_server_group" {
  description = "Default server group"
  default     = {}
}

variable "default_metadata" {
  description = "Default metadata"
  default     = {
    test_meta = "Created by Terraform VM_module"
  }
}

variable "VMs" {
  description = "VMs list source"
  default = {}
}

# user_data = "#cloud-config\nhostname: instance_1.example.com\nfqdn: instance_1.example.com"
variable "default_user_data" {
  description = "Default user data"
  default = ""
}

validation {
  condition = alltrue([
    for k, v in var.VMs :
      v.server_group == null || v.server_group_name == null
  ])
  error_message = "Cannot specify both server_group and server_group_name for the same VM"
}