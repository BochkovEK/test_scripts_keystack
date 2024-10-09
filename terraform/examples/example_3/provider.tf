#foo
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
#     cloud = "openstack"
##    endpoint_overrides = {
##        "volumev3" = var.volumev3
##    }
#}

provider "openstack" {
 user_name = "admin"
 tenant_name = openstack_identity_project_v3.test_project.id

 #"admin"
 password = "cwW1aI9UkrbcwrInjbaU4OWWfJ2sIJtmPDJLpXpW"
 auth_url = "http://myauthurl:5000/v2.0"
 region = "RegionOne"
}

resource "openstack_identity_project_v3" "test_project" {
name = "test_project_terraform"
description = "Created by Terraform"
}

resource "openstack_identity_user_v3" "admin" {
name = "admin"
default_project_id = openstack_identity_project_v3.test_project.id
}