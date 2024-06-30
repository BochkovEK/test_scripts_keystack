## Features
- Create 2 (two) AZs
- Create VMs in AZ
### To start:
- Install Terraform
- Create base openstack resources:
  - Network (pub_net)
  - Security group with allowed ping, ssh (test_security_group)
  - Images (ubuntu-20.04-server-cloudimg-amd64, cirros-0.6.2-x86_64-disk)
  - Flavors (1c-1r, 2c-2r, ... 8c-2r)
  - Key pair for access to VM (key_test)
- Define variables in <name>.auto.tfvars
- Run following commands in folders with <main.tf>:
  - terraform init
  - terraform plan -var-file "<name>.auto.tfvars"
  - terraform apply
### To destroy terraform creation:
- Run following command in folders with <main.tf>:
  - terraform destroy