output "debug_disk_attachments" {
  value = [for k, v in local.disk_attachments : keys(v.disk_config)]
}