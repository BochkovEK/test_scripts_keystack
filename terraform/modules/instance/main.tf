# Using recommended by VKCS version of Openstack
terraform {
    required_providers {
        openstack = {
        source = "terraform-provider-openstack/openstack"
        version = ">= 1.33.0"
        }
    }
}

provider "openstack" {
    cloud = "openstack"
    endpoint_overrides = {
        "volumev2" = "https://10.224.143.100:8776/v3/63f0b7d97e5347c1952bab9052c527f9"
    }
}
