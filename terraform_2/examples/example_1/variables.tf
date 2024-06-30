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

variable "network_name" {
  description = "Network name"
  type        = string
}

variable "security_groups" {
  description = "Security group name"
  type        = list(string)
}
