module "ubuntu-vm" {
    source          = "../../modules/instance"
    name            = "ubuntu-vm"
    flavor          = "Standard-4-8-80"
    image           = "Ubuntu-20.04.1-202008"
    ssh_key_name    = "ansible-key"
    metadata        = {
            os_ver  = "ubuntu20"
        }
    ports = [
        {
            network         = "network-1"
            subnet          = ""
            ip_address      = ""
            dns_record      = true
            dns_zone        = "example.com."
            security_groups = ["i_default","o_default"]
            security_groups_ids = []
        }
    ]
    volumes = var.volumes
}