variable "vm_name" {
  description = "VM name"
  type        = string
}

variable "image_name" {
  description = "Image name"
  type        = string
}

variable "flavor_name" {
  description = "Flavor name"
  type        = string
}

variable "keypair_name" {
  description = "Key pair name"
  type        = string
}

# Volume size in GB
variable "volume_size" {
  type = number
  default = 5
}

variable "network_name" {
  description = "Network name"
  type        = string
}

variable "security_groups" {
  description = "Security group name"
  type        = list(string)
}

variable "vm_qty" {
  description = "Count vms created"
  type        = string
}

variable "az_name" {
  default = ""
  type = string
}