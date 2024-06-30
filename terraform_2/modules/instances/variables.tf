variable "vm_name" {
  type        = string
}

variable "image_name" {
  type        = string
}

variable "flavor_name" {
  type        = string
}

variable "keypair_name" {
  type        = string
}

variable "network_name" {
  type        = string
}

#variable "vm_qty" {
#  type        = string
#}

variable "security_groups" {
  description = "Security group name"
  type        = list(string)
}

variable "az_hints" {
  type        = string
}
