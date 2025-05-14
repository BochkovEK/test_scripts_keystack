# VMs
VMs = {
  TEST_VM = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    #    image_name = "test_cirros"
    vm_qty     = 4
    flavor     = {
      vcpus = 2
      ram   = 2048
      extra_specs = {
        "hw:mem_page_size" = "large"  # Включает большие страницы
        }
    }
    disks = [
      {
        boot_index = 1,
        size       = 1
      },
      {
        boot_index = 2,
        size       = 2
      }
    ]
  }
  TEST_VM_after_fail = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    #    image_name = "test_cirros"
    vm_qty     = 4
    flavor     = {
      vcpus = 2
      ram   = 2048
      extra_specs = {
        "hw:mem_page_size" = "large"  # Включает большие страницы
        }
    }
    disks = [
      {
       boot_index = 1,
        size       = 1
      },
      {
        boot_index = 2,
        size       = 2
      }
    ]
  }
  TEST_VM_after_raiseup = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    #    image_name = "test_cirros"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
      extra_specs = {
        "hw:mem_page_size" = "any"  # Включает большие страницы
        }
    }
    disks = [
      {
        boot_index = 1,
        size       = 1
      },
      {
        boot_index = 2,
        size       = 2
      }
    ]
  }
}

# AZs
AZs = {
}

server_groups = {}