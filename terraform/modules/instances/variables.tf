## VM
variable "default_image_name" {
  description = "Default image name"
  type        = string
  default = "cirros-0.6.2-x86_64-disk"
}

#variable "default_flavor_name" {
#  description = "Default flavor name"
#  type        = string
#  default = "2c-2r"
#}

variable "default_flavor" {
#  description = "Default flavor name"
  default = {
    vcpus = 2
    ram   = 2048
  }
}

variable "default_disk" {
  description = "Default disk"
  default = {
    sda = 5
  }
}

variable "default_boot_volume_size" {
  description = "Default volume size"
  type        = number
  default = 5
}

variable "default_network_name" {
  description = "Default network name"
  type        = string
  default = "pub_net"
}

variable "default_security_groups" {
  description = "Default security_groups"
  type        = list(string)
  default = ["test_security_group"]
}

variable "default_key_pair_name" {
  description = "Default key pair"
  type        = string
  default = "key_test"
}

variable "default_az_hints" {
  description = "Default availability zone hints"
  type        = string
  default     = ""
}

variable "VMs" {
  description = "VMs list source"
  default = {}
}

variable "AZs" {
  description = "AZs list source"
  default = {}
}
