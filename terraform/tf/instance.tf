module "ubuntu-vm" {
    source          = "/root/tf-openstack-vkcs-vm"
    name            = "ubuntu-vm"
    flavor          = "2c-2r_admin"
    image           = "ubuntu-20.04-server-cloudimg-amd64"
    ssh_key_name    = "key_test"
    az              = "nova"
    metadata        = {
            os_ver  = "ubuntu20"
        }
    ports = [
        {
            network         = "pub_net"
            subnet          = ""
            ip_address      = ""
            dns_record      = false
            dns_zone        = ""
            security_groups = ["test_security_group"]
            security_groups_ids = []
        }
    ]
    volumes = {
        root = {
            type            = "__DEFAULT__"
            size            = 5
        }
    }
}

module "cirros-vm" {
    source          = "/root/tf-openstack-vkcs-vm"
    name            = "cirros-vm"
    flavor          = "2c-2r_admin"
    image           = "cirros-0.6.2-x86_64-disk"
    metadata        = {
            os_ver  = "cirros6"
        }
    ports = [
        {
            network         = "pub_net"
            subnet          = ""
            ip_address      = ""
            dns_record      = false
            dns_zone        = ""
            security_groups = ["test_security_group"]
            security_groups_ids = []
        }
    ]
    volumes = {
        root = {
            type            = "__DEFAULT__"
            size            = 5
        }
    }
}