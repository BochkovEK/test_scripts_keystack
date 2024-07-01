variable "VMs" {
  description = "VMs list source"
  default = {
  }
}

variable "AZs" {
  description = "AZs list source"
  default = {}
}

#variable "AZs"{
#  description = "List of AZs"
#  type = map (object({
#    az_name = string
#    hosts_list = list(string)
#  }))
#  default = {}
#}