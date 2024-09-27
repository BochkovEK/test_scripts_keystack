## Features
- Create AZs
- Create VMs in AZ
### To start:
- <details>
  <summary>Install <b>openstack cli</b></summary>
  
  Sberlinux:
         
      yum install -y python3-pip
      python3 -m pip install openstackclient
      export PATH=\$PATH:/usr/local/bin
  </details>

- Create base openstack resources (required):
  - <details>
    <summary>Network (<b>pub_net</b>)</summary>

    1. Define <b>CIDR</b> and <b>GATEWAY</b> (for itkey stands on LCM or jump host):

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
            allocation_start="10.224.130.10"
            allocation_end="10.224.128.30"
    3. Create network and subnet:
     
           openstack network create --external --share --provider-network-type flat --provider-physical-network physnet1 pub_net;
           openstack subnet create --subnet-range $CIDR --network pub_net --dhcp --gateway $GATEWAY --allocation-pool start=$allocation_start,end=$allocation_end pub_subnet

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
    <summary>Key pair for access to VM (<b>key_test</b>)</summary>
    
    To the key pair for the user, specified in the cloud.yml based on $HOME/test_scripts_keystack/key_test.pem:
    
        openstack keypair create key_test --public-key $HOME/test_scripts_keystack/key_test.pub
    </details>
- <details>
  <summary>Install <b>Terraform</b></summary>

  Install wget:
      
      #Sberlinux
      yum in -y wget
  
      #Ubuntu
      apt install wget
  
  Download Terraform binary from repo itkey:

      wget https://repo.itkey.com/repository/bootstrap/terraform/terraform_1.8.5_linux_amd64
  
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
### To create VMs\AZ:
- <details>
  <summary>Add <b>clouds.yml</b> to "main.tf" directory</summary>
  
  Create clouds.yml

      vi clouds.yml
  
  Past into clouds.yml next template and define your parameters: <b>VIP, project_id, password, region_name</b>.
      
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
        flavor            = {
            vcpus         = Number of vCPUs (flavor)
            ram           = RAM in !!!MB (1024, 2048, 4096, ...) (flavor)
        }                 if not define create flavor vcpus = 2, ram = 2048
        keypair_name      = The key pair name for the user specified in the cloud.yml (default: key_test)
        security_groups   = The name of the security group from the project specified in the cloud.yml (default: test_security_group)
        az_hint           = The AZ name if neded. Valid format: "<az_name>" or "<az_name>:<hypervisor_name>" 
        disks             = [
           {
             boot_index = 1
             size       = Size in GB
           },
             ...
           }
             boot_index = 2
             size       = Size in GB
           },
           ...
           {
             boot_index = n
             size       = Size in GB
           },
        ]                   List of dictionaries
        network_name      = The name of network (default: pub_net)

    The first <b>minimal</b> auto.vars file looks like (create one VM):

        # VMs
        VMs = {
            TEST_VM = {
                vm_qty = 1
            }
        }

        # AZs
        AZs = {}

    The second <b>minimal</b> auto.vars file looks like (create just AZ):

        # VMs
        VMs = {
        }

        # AZs
        AZs = {
           <aggr_name> = {
               az_name = "<az_name>"
               hosts_list = [
                   "<comp_node_name>",
               ]
           }
        }

    Example of creating an auto.vars file:

      cat <<-EOF > ~/test_scripts_keystack/terraform/examples/example_1/foo.auto.tfvars
        # VMs
        VMs = {
          TEST_VM_1 = {
            vm_qty          = 1
            image_name      = "ubuntu-20.04-server-cloudimg-amd64"
            az_hint         = "az_1:ebochkov-ks-sber-comp-01"
            }
          TEST_VM_2 = {
            vm_qty          = 2
            image_name      = "cirros-0.6.2-x86_64-disk"
            flavor          = {
              vcpus = 4
            }
            disks           = [
              {
                boot_index = 1
                size       = 7
              },
              {
                boot_index = 2
                size       = 8
              }
            ]
          }
          TEST_VM_3 = {
            vm_qty          = 3
            image_name      = "cirros-0.6.2-x86_64-disk"
            flavor          = {
              ram         = 1024
            }
            disks           = [
              {
                boot_index = 1
                size       = 3
              }
            ]
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
  - or 
  - terraform apply -auto-approve

### To destroy terraform creation:
- Run following command in folders with <main.tf>:
  - terraform destroy
    - type "yes"