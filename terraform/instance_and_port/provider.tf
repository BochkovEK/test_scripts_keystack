terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.48.0"
    }
  }
}

# Configure the OpenStack Provider
provider "openstack" {
  user_name   = "admin"
  tenant_name = "admin"
  password    = "d1D73NQjpO5GuKlFspR0BX3PAt8fF55BZThs3sYf"
  auth_url    = "https://int.ebochkov.test.domain:5000/v3"
  region      = "ebochkov"
  cacert_file = "/root/root/ca-bundle.crt"
}
#provider "openstack" {
#     cloud = "openstack"
##    endpoint_overrides = {
##        "volumev3" = var.volumev3
##    }
#}