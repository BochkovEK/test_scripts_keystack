# Configure the OpenStack Provider
provider "openstack" {
  user_name   = "admin"
  tenant_name = "admin"
  password    = "d1D73NQjpO5GuKlFspR0BX3PAt8fF55BZThs3sYf"
  auth_url    = "https://int.ebochkov.test.domain:5000/v3"
  region      = "ebochkov"
  cacert_file = "/root/ca-bundle.crt"
}