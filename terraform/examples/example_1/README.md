## Features
- Create AZs
- Create VMs in AZ
### To start:
- Install Terraform
- Create base openstack resources:
 <details>
  <summary><b>Network</b> (pub_net):</summary>
  
  1) Define <b>CIDR</b> and <b>GATEWAY</b> (for itkey stands)  

    CIDR=$(ip r|grep "dev external proto kernel scope"| awk '{print $1}');
    last_digit=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\.[0-9]+\.[0-9]+\.)|(\/[0-9]+)//g');
    left_side=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\/[0-9]+)//g')
    GATEWAY=$left_side$(expr $last_digit + 1)
    echo "CIDR: $CIDR, GATEWAY: $GATEWAY"

  2) Define `--allocation-pool start=<start_IP> ,end=<end_IP>` from table for `/27`  mask:
  Network address Usable IP addresses  Broadcast address: 
  ```.0    .1-.30    .31
  .32   .33-.62   .63
  .64   .65-.94   .95
  .96   .97-.126  .127
  .128  .129-.158 .159
  .160  .161-.190 .191
  .192  .193-.222 .223
  .224  .225-.254 .255
  ```
  ```
  Example:

  if CIDR 10.224.130.0/27
  allocation_start = "10.224.130.10"
  allocation_end   = "10.224.128.30"
  ```
  3) Create network and subnet:
     
    openstack network create --external --share --provider-network-type flat --provider-physical-network physnet1 pub_net
    subnet create --subnet-range $CIDR --network pub_net --dhcp --gateway $GATEWAY --allocation-pool start=<start>,end=<end> pub_subnet

</details>

  - Security group with allowed ping, ssh (test_security_group)
  - Images (ubuntu-20.04-server-cloudimg-amd64, cirros-0.6.2-x86_64-disk)
  - Flavors (1c-1r, 2c-2r, ... 8c-2r)
  - Key pair for access to VM (key_test)
- Define variables in <name>.auto.tfvars
- Add clouds.yml to <main.tf> directory
- Run following commands in folders with <main.tf>:
  - terraform init
  - terraform plan -var-file "<name>.auto.tfvars"
  - terraform apply
### To destroy terraform creation:
- Run following command in folders with <main.tf>:
  - terraform destroy