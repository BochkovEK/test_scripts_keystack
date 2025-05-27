# VMs
VMs = {
  TEST_VM_1 = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    az_hint    = "nova:cdm-bl-pca10"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
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
  TEST_VM_2 = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    az_hint    = "nova:cdm-bl-pca11"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
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
  TEST_VM_3 = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    az_hint    = "nova:cdm-bl-pca12"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
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