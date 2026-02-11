terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">=1.42.0"
    }
  }
  required_version = ">= 0.13"
}
