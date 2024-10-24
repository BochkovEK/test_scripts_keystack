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
#     cloud = "openstack"
  user_name: "admin"
  tenant_name: "admin"
  password: "56OnOHXYLVdsS5a46cdFXct2c9kI2vzYK3uivdFd"
  auth_url: "https://int.ebochkov.test.domain:5000"
  region_name: "ebochkov"
  user_domain_name: "Default"
  project_id: bee56048988140faa81bc8d30fc07b1f
  interface: "public"
  identity_api_version: 3
      #cacert: "~/bundle.crt"
      #insecure: true
  insecure = "true"
}

#    endpoint_overrides = {
#        "volumev3" = var.volumev3
#    }
#}