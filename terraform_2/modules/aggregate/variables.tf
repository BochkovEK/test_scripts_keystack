#variable "aggr_name" {
#  type = string
#}
#
#variable "az_name" {
#  type = string
#}
#
#variable "hosts_list" {
#  type = list(string)
#}

variable "AZs"{
  description = "List of AZs"
  type = map (object({
    az_name = string
    hosts_list = list(string)
  }))
}