output "server_group_types" {
  value = {
    for inst in local.instances :
    inst.name => inst.server_group_type
  }
  description = "Server group types for all instances"
}
