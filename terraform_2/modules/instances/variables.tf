## VM
variable "default_image_name" {
  description = "Default image name"
  type        = string
  default = "cirros-0.6.2-x86_64-disk"
}

variable "default_flavor_name" {
  description = "Default flavor name"
  type        = string
  default = "2c-2r"
}

variable "default_volume_size" {
  description = "Default volume size"
  type        = number
  default = 5
}

variable "default_network_name" {
  description = "Default network name"
  type        = string
  default = "pub_net"
}

#variable "default_az_hints" {
#  description = "Default availability zone hints"
#  type        = string
#  default     = ""
#}

variable "VMs"{
  description = "List of VMs"
  type = map (object({
    vm_name         = string
    image_name      = string
    flavor_name     = string
    keypair_name    = string
    volume_size     = number
    network_name    = string
    security_groups = list(string)
    az_hint         = string
    vm_qty          = number
  }))
}