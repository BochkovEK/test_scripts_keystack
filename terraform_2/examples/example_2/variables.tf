### VM
#variable "default_image_name" {
#  description = "Default image name"
#  type        = string
#  default = "cirros-0.6.2-x86_64-disk"
#}
#variable "flavor_name" {
#  description = "Flavor name"
#  type        = string
#}
#variable "keypair_name" {
#  description = "Key pair name"
#  type        = string
#}
#
## Volume size in GB
#variable "volume_size" {
#  type = number
#  default = 5
#}
#
#variable "network_name" {
#  description = "Network name"
#  type        = string
#}
#variable "security_groups" {
#  description = "Security group name"
#  type        = list(string)
#}
#variable "vm_qty" {
#  description = "Count vms created"
#  default     = "1"
#  type        = string
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
    vm_qty          = number
    az_hint         = string
  }))
  default = {}
}

variable "AZs"{
  description = "List of AZs"
  type = map (object({
    az_name = string
    hosts_list = list(string)
  }))
  default = {}
}

## AZ_1
#variable "aggr_name_1" {
#  type = string
#}
#variable "az_name_1" {
#  type = string
#}
#variable "hosts_list_1" {
#  type = list(string)
#}
#variable "vms_count_1" {
#  type = string
#}
#variable "vm_name_1" {
#  type = string
#}
#
#
## AZ_2
#variable "aggr_name_2" {
#  type = string
#}
#variable "az_name_2" {
#  type = string
#}
#variable "hosts_list_2" {
#  type = list(string)
#}
#variable "vms_count_2" {
#  type = string
#}
#variable "vm_name_2" {
#  type = string
#}


