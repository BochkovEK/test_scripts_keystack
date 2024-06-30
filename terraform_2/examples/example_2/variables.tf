# VM

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

variable "vm_qty" {
  description = "Count vms created"
  type        = string
}

# AZ_1
variable "name_aggr_1" {
  type = string
}
variable "name_az_1" {
  type = string
}
variable "hosts_list_1" {
  type = list(string)
}
variable "vms_count_1" {
  type = string
}
variable "vm_name_1" {
  type = string
}


# AZ_2
variable "name_aggr_2" {
  type = string
}
variable "name_az_2" {
  type = string
}
variable "hosts_list_2" {
  type = list(string)
}
variable "vms_count_2" {
  type = string
}
variable "vm_name_2" {
  type = string
}


