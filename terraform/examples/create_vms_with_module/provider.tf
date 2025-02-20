terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.48.0"
    }
  }
}

# authentication by clouds.yml file
#----------------------------------
#provider "openstack" {
#  cloud = "openstack"
#}

# MTSL (two-factor authentication)
#----------------------------------
provider "openstack" {
  user_name        = "admin"
  tenant_name      = "admin"
  password         = "56OnOHXYLVdsS5a46cdFXct2c9kI2vzYK3uivdFd"
  auth_url         = "https://int.ebochkov.test.domain:5000"
  user_domain_name = "Default"
#  insecure         = "true"
  cert              = "/root/client.crt"
  key               = "/root/cert.key"
#  cacert_file      = "/installer/data/ca/root/ca.crt"

}