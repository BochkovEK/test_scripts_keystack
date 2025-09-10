VMs = {
    vm_haproxy_test = {
        vm_qty              = 15
        image_name          = "cirros-0.6.2-x86_64-disk.img"
        az_hint             = "nova:cdm-bl-pca10"
        boot_volume_size    = 1
        disks               = [
            {
                boot_index  = 1
                size        = 1
            },
            {
                boot_index  = 2
                size        = 2
            },
            {
                boot_index  = 3
                size        = 3
            },
            {
                boot_index  = 4
                size        = 4
            }
        ]
    }
}