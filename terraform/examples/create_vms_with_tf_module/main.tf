# if need when copying create_vms_with_tf_module to another location, it is necessary to change the path to the module
# source = /absolute/path/to/test_scripts_keystack/terraform/modules

module "VMs" {
    source = "../../modules/instances"
    VMs    = var.VMs
}