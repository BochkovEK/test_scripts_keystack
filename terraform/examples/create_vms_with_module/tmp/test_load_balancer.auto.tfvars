# Download the image (example for version 5.5.0)
#wget https://tarballs.opendev.org/openstack/octavia/test-images/test-only-amphora-x64-haproxy-ubuntu-bionic.qcow2

# Upload image to Glance
#openstack image create "amphora-image" \
#  --container-format bare \
#  --disk-format qcow2 \
#  --tag amphora \
#  --file test-only-amphora-x64-haproxy-ubuntu-bionic.qcow2 \
#  --public

# Create flavor
#openstack flavor create --id 200 --vcpus 1 --ram 1024 --disk 2 m1.amphora

# Create security group
#openstack security group create lb-mgmt-sec-grp

# Management rules
#openstack security group rule create --protocol tcp --dst-port 22:9443 lb-mgmt-sec-grp
#openstack security group rule create --protocol icmp lb-mgmt-sec-grp

# Traffic rules
#openstack security group rule create --protocol tcp --dst-port 80 lb-mgmt-sec-grp
#openstack security group rule create --protocol tcp --dst-port 443 lb-mgmt-sec-grp

# Create network
#openstack network create lb-mgmt-net

# Create subnet
#openstack subnet create lb-mgmt-subnet \
#  --network lb-mgmt-net \
#  --subnet-range 10.10.10.0/24 \
#  --allocation-pool start=10.10.10.2,end=10.10.10.254

# Create keypair
#openstack keypair create --public-key ~/test_scripts_keystack/key_test.pub my-key

# VMs
VMs = {
  TEST_VM = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    #    image_name = "test_cirros"
    vm_qty     = 2
    flavor     = {
      vcpus = 2
      ram   = 2048
      extra_specs = {
        "hw:mem_page_size" = "large"  # Включает большие страницы
        }
    }
  }
}

# AZs
AZs = {
}

server_groups = {}