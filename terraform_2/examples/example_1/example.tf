module "ubuntu-vm" {
    source          = "../../modules/instances"
    vm_name         = var.vm_name
    image_name      = var.image_name
    keypair_name    = var.keypair_name
    network_name    = var.network_name
    flavor_name     = var.flavor_name
    security_groups = var.security_groups
    vm_qty          = var.vm_qty
    az_hints        = var.az_name
    volume_size     = var.volume_size
}
