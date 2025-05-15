# Скачать образ (пример для версии 5.5.0)
#wget https://tarballs.opendev.org/openstack/octavia/test-images/test-only-amphora-x64-haproxy-ubuntu-bionic.qcow2

# Загрузить образ в Glance
#openstack image create "amphora-image" \
#  --container-format bare \
#  --disk-format qcow2 \
#  --tag amphora \
#  --file test-only-amphora-x64-haproxy-ubuntu-bionic.qcow2 \
#  --public

# Создать flavor
#openstack flavor create --id 200 --vcpus 1 --ram 1024 --disk 2 m1.amphora

# Создаем security group
#openstack security group create lb-mgmt-sec-grp

# Правила для управления
#openstack security group rule create --protocol tcp --dst-port 22:9443 lb-mgmt-sec-grp
#openstack security group rule create --protocol icmp lb-mgmt-sec-grp

# Правила для трафика
#openstack security group rule create --protocol tcp --dst-port 80 lb-mgmt-sec-grp
#openstack security group rule create --protocol tcp --dst-port 443 lb-mgmt-sec-grp

# Создание сети
#openstack network create lb-mgmt-net

# Создание подсети
#openstack subnet create lb-mgmt-subnet \
#  --network lb-mgmt-net \
#  --subnet-range 10.10.10.0/24 \
#  --allocation-pool start=10.10.10.2,end=10.10.10.254

#openstack keypair create --public-key ~/test_scripts_keystack/key_test.pub my-key

# VMs
VMs = {
  TEST_VM = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    #    image_name = "test_cirros"
    vm_qty     = 2
    network_name = "lb-mgmt-net"
    security_groups = "lb-mgmt-sec-grp"
    keypair_name = "my-key"
    flavor     = {
      vcpus = 2
      ram   = 2048
      extra_specs = {
        "hw:mem_page_size" = "large"  # Включает большие страницы
        }
    }
  }
#  TEST_VM_after_fail = {
#    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
#    #    image_name = "test_cirros"
#    vm_qty     = 4
#    flavor     = {
#      vcpus = 2
#      ram   = 2048
#      extra_specs = {
#        "hw:mem_page_size" = "large"  # Включает большие страницы
#        }
#    }
#    disks = [
#      {
#       boot_index = 1,
#        size       = 1
#      },
#      {
#        boot_index = 2,
#        size       = 2
#      }
#    ]
#  }
#  TEST_VM_after_raiseup = {
#    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
#    #    image_name = "test_cirros"
#    vm_qty     = 1
#    flavor     = {
#      vcpus = 2
#      ram   = 2048
#      extra_specs = {
#        "hw:mem_page_size" = "any"  # Включает большие страницы
#        }
#    }
#    disks = [
#      {
#        boot_index = 1,
#        size       = 1
#      },
#      {
#        boot_index = 2,
#        size       = 2
#      }
#    ]
#  }
}

# AZs
AZs = {
}

server_groups = {}