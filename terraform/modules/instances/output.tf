output "server_group_types" {
  value = {
    for inst in local.instances :
    inst.name => {
       type = inst.server_group_type
       uuid = inst.server_group_uuid
    }
  }
  description = "Server group types for all instances"
}
