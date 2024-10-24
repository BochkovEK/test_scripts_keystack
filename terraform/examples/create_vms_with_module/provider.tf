terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.48.0"
    }
  }
}

#provider "openstack" {
#  cloud = "openstack"
#}

provider "openstack" {
  user_name        = "admin"
  tenant_name      = "admin"
  password         = "56OnOHXYLVdsS5a46cdFXct2c9kI2vzYK3uivdFd"
  auth_url         = "https://int.ebochkov.test.domain:5000"
  user_domain_name = "Default"
#  insecure         = "true"
  cert              = "client.ctr"
  key               = "cert.key"

}