#variable "server_group_name" {
#  description = "server group name"
#  default = ""
#}
#
#variable "server_group_policies" {
#  description = "server group policies"
#  default = []
#}

variable "server_groups" {
  description = "default server group"
  default = {}
}

variable "server_group" {
  description = "default server group"
  default = {
#    name =
#  policies = var.server_group.policies
  }
}

#  server_groups = {
#  foo = {
#    policies = ["affinity"]
#  }
#  bar = {
#    policies = ["anti-affinity"]
#  }