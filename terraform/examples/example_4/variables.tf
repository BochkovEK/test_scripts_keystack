variable "public_dns" {
  default = ["192.168.21.28"]
}

variable "keypair" {
  description = "Please define keypair name if team need to be overrided"
  default     = "key_test"
}

variable "image_name" {
  description = "Please image name"
#  default     = "ubuntu-20.04-server-cloudimg-amd64"
  default     = "ubuntu-22.04-x64"
}

variable "subnetpool" {
  default = "lab_sk_bgp"
}

variable "image_user" {
  default = "ubuntu"
}

variable "pub_net" {
  description = "Please specify public network name"
  default     = "pub_net"
}

variable "qty" {
  default     = 1
}

