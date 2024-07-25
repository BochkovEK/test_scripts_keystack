## Features
- Create AZs
- Create VMs in AZ
### To start:
- Install openstack cli
- <details>
  <summary>Install <b>Terraform</b></summary>
  
  Download Terraform binary from repo itkey:

      wget https://repo.itkey.com/repository/images/terraform_1.8.5_linux_amd64
  
  Change the access permissions:

      chmod 777 ./terraform_1.8.5_linux_amd64

  Move binary to /usr/local/bin/:

      mv terraform_1.8.5_linux_amd64 /usr/local/bin/terraform

  Change terraform provider_installation:

      cat <<-EOF > ~/.terraformrc
      provider_installation {
          network_mirror {
              url = "https://terraform-mirror.yandexcloud.net/"
              include = ["registry.terraform.io/*/*"]
          }
          direct {
              exclude = ["registry.terraform.io/*/*"]
          }
      }
      EOF
  </details>
- Create base openstack resources:
  - <details>
    <summary>Network (<b>pub_net</b>)</summary>

    1. Define <b>CIDR</b> and <b>GATEWAY</b> (for itkey stands):

           CIDR=$(ip r|grep "dev external proto kernel scope"| awk '{print $1}');
           last_digit=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\.[0-9]+\.[0-9]+\.)|(\/[0-9]+)//g');
           left_side=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\/[0-9]+)//g');
           GATEWAY=$left_side$(expr $last_digit + 1);
           echo "CIDR: $CIDR, GATEWAY: $GATEWAY"
    2. Define `--allocation-pool start=<start_IP> ,end=<end_IP>` from table for `/27`  mask:
   Network address Usable IP addresses  Broadcast address:
           
           .0    .1-.30    .31
           .32   .33-.62   .63
           .64   .65-.94   .95
           .96   .97-.126  .127
           .128  .129-.158 .159
           .160  .161-.190 .191
           .192  .193-.222 .223
           .224  .225-.254 .255
           
            Example:

            if CIDR 10.224.130.0/27
            allocation_start = "10.224.130.10"
            allocation_end   = "10.224.128.30"
    3. Create network and subnet:
     
           openstack network create --external --share --provider-network-type flat --provider-physical-network physnet1 pub_net;
           openstack subnet create --subnet-range $CIDR --network pub_net --dhcp --gateway $GATEWAY --allocation-pool start=<start>,end=<end> pub_subnet

    </details>
  - <details>
    <summary>Security group with allowed ping, ssh (<b>test_security_group</b>)</summary>
    
    To crete test_security_group:
  
        SECURITY_GR_ID=$(openstack security group create test_security_group|grep "id"| head -1 | awk '{print $4}')
        openstack security group rule create --egress --ethertype IPv4 --protocol tcp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol tcp $SECURITY_GR_ID
        openstack security group rule create --egress --ethertype IPv4 --protocol udp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol udp $SECURITY_GR_ID
        openstack security group rule create --ingress --ethertype IPv4 --protocol icmp $SECURITY_GR_ID
    </details>
  - <details>
    <summary>Image (<b>cirros-0.6.2-x86_64-disk</b>)</summary>
    
    To crete cirros-0.6.2-x86_64-disk:
  
        wget https://repo.itkey.com/repository/images/cirros-0.6.2-x86_64-disk.img -O cirros-0.6.2-x86_64-disk.img
        openstack image create cirros-0.6.2-x86_64-disk --disk-format qcow2 --min-disk 1 --container-format bare --public --file ./cirros-0.6.2-x86_64-disk.img
    To crete ubuntu-20.04-server-cloudimg-amd64:
  
        wget https://repo.itkey.com/repository/images/ubuntu-20.04-server-cloudimg-amd64.img -O ubuntu-20.04-server-cloudimg-amd64.img
        openstack image create ubuntu-20.04-server-cloudimg-amd64 --disk-format qcow2 --min-disk 5 --container-format bare --public --file ./ubuntu-20.04-server-cloudimg-amd64.img
    </details>
  - <details>
    <summary>Flavor (<b>2c-2r</b>)</summary>
    
    To crete flavor 2c-2r:
  
         openstack flavor create --vcpus 2 --ram 2048 --disk 0 2c-2r
    </details>
  - <details>  
    <summary>Key pair for access to VM (<b>key_test</b>)</summary>
    
    To the key pair for the user, specified in the cloud.yml based on $HOME/test_scripts_keystack/key_test.pem:
    
         openstack keypair create key_test --public-key $HOME/test_scripts_keystack/key_test.pub
    </details>

### To create:
- <details>
  <summary>Add <b>clouds.yml</b> to "main.tf" directory</summary>
  
  Create clouds.yml

      vi clouds.yml
  
  Past into clouds.yml next template and define your parameters: VIP, project_id, password, region_name.
      
      clouds:
          openstack:
              auth:
              auth_url: https://<VIP>:5000
              username: "admin"
              project_id: <project_id>
              project_name: "admin"
              user_domain_name: "Default"
              password: <password>
              region_name: "<region_name>"
              interface: "public"
              identity_api_version: 3

  Vim shortcut:

      I                           - Instrt text
      Press "Esc" and type ":wq"  - Save and exit

  Move the clouds.yml to $HOME/test_scripts_keystack/terraform/examples/example_1

      mv ./clouds.yml $HOME/test_scripts_keystack/terraform/examples/example_1/clouds.yml
  </details>
- <details>
  <summary>Define variables in <b>name.auto.tfvars</b></summary>
  
  Creating a VMs is based on the following dictionaries:

      # VMs
      VMs = {
          <base_VMs_name_1> = {
              <porperties_1...>
          }
          <base_VMs_name_2> = {
              <porperties_2...>
          }
          ...
          <base_VMs_name_n> = {
              <porperties_n...>
          }
      }
    
      # AZs
      AZs = {
          <aggr_name_1> = {
              az_name = "<az_name_1>"
              hosts_list = [
                  "<comp_name_1_1>",
                  "<comp_name_1_2>",
                  ...,
                 "<comp_name_1_n>"
              ]
          <aggr_name_2> = {
              az_name = "<az_name_2>"
              hosts_list = [
                  "<comp_name_2_1>",
                  "<comp_name_2_2>",
                  ...,
                 "<comp_name_2_n>"
              ]
          }
         ...
         <aggr_name_n> = {
              az_name = "<az_name_n>"
              hosts_list = [
                  "<comp_name_n_1>",
                  "<comp_name_n_2>",
                  ...,
                 "<comp_name_n_n>"
              ]
      }

  List of accepted VM properties:

      vm_qty            = !!! Required parameter. Quantity of created VMs
      image_name        = The name of the image from the project specified in the cloud.yml (default: cirros-0.6.2-x86_64-disk)
      flavor_name       = The name of the flavor from the project specified in the cloud.yml (default: 2c-2r)
      keypair_name      = The key pair name for the user specified in the cloud.yml (default: key_test)
      security_groups   = The name of the security group from the project specified in the cloud.yml (default: test_security_group)
      az_hint           = The AZ name if neded
      volume_size       = Volume size (default: 5 GB)
      network_name      = The name of network (default: pub_net)

  the <b>minimal</b> auto.vars file looks like:

      # VMs
      VMs = {
          TEST_VM = {
              vm_qty = 1
          }
      }

      # AZs
      AZs = {}

  Example of creating an auto.vars file:

      cat <<-EOF > ~/test_scripts_keystack/terraform/examples/example_1/foo.auto.tfvars
      # VMs
      VMs = {
          TEST_DRS = {
              image_name      = "ubuntu-20.04-server-cloudimg-amd64"
              flavor_name     = "2c-2r"
              vm_qty          = 3
              az_hint         = "az_1:ebochkov-ks-sber-comp-01"
          }
      }
    
      # AZs
      AZs = {
          aggr_1 = {
              az_name = "az_1"
              hosts_list = [
                  "ebochkov-ks-sber-comp-01",
                  "ebochkov-ks-sber-comp-02",
              ]
          }
          aggr_2 = {
              az_name    = "az_2"
              hosts_list = [
                  "ebochkov-ks-sber-comp-03",
                  "ebochkov-ks-sber-comp-04",
              ]
          }
      }
      EOF
  </details>
- Run following commands in folders with <main.tf> ($HOME/test_scripts_keystack/terraform/examples/example_1):
  - terraform init
  - terraform plan -var-file "\<name>.auto.tfvars"
  - terraform apply
    - type "yes"

### To destroy terraform creation:
- Run following command in folders with <main.tf>:
  - terraform destroy