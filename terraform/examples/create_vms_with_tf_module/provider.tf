terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.48.0"
    }
  }
}

# authentication by clouds.yml file or ENVs
#----------------------------------
provider "openstack" {
  cloud = "openstack"
}

# MTSL (two-factor authentication)
#----------------------------------
#provider "openstack" {
#  user_name        = "admin"
#  tenant_name      = "admin"
#  password         = "<password>"
#  auth_url         = "https://<internal_fqdn\external_fqdn>:5000"
#  user_domain_name = "Default"
##  insecure         = "true"
#  cert              = "/path/to/cert.pem"
#  key               = "/path/to/key.pem"
##  cacert_file      = "/path/to/ca.crt"
#}