# VMs
VMs = {
  vm1 = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    az_hint    = "nova:cdm-bl-pca10"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
    }

    user_data = {
      template_file = "templates/cloud-init-1-3.yaml"  # Path to template file
    }
  }
  vm2 = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    az_hint    = "nova:cdm-bl-pca11"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
    }


    user_data = {
      template_file = "templates/cloud-init-2.yaml"
    }
  }
  vm3 = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    az_hint    = "nova:cdm-bl-pca12"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
    }
    user_data = {
      template_file = "templates/cloud-init-1-3.yaml"
    }
  }
}

# AZs
AZs = {
}

server_groups = {}