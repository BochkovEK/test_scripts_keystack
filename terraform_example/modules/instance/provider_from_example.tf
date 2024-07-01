terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.48.0"
    }
  }
}

provider "openstack" {

    cloud = "openstack"
    endpoint_overrides = {
        "volumev3" = var.volumev3
    }
}
