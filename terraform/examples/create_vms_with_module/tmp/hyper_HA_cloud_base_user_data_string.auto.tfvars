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
    user_date = "#cloud-config\nchpasswd:\n  expire: false\n  users:\n    - name: ubuntu\n      password: \"$6$1RIJCwfWrd3WqaPd$sKcB5WNabsMQmCl3mu1JwJUsyrgNJdux5Ahj/6e1o79RRIyDwCjjEh44lqbo18T3lmOxfHuzlXpTwfvebO7S61\"\n      type: hash\nssh_pwauth: true\n\nwrite_files:\n  - path: /etc/systemd/resolved.conf\n    content: |\n      [Resolve]\n      DNS=8.8.8.8 8.8.4.4 77.88.8.8\n      FallbackDNS=1.1.1.1\n      Domains=~.\n\nruncmd:\n  - echo \"Custom cloud-init commands started executing...\" >> /var/log/cloud-init-output.log\n  - systemctl restart systemd-resolved\n  - |\n    for i in {1..6}; do\n      apt-get update && apt-get install -y iperf3 && break || sleep 10\n    done\n  - systemctl daemon-reload\n  - systemctl start disk_check.service\n  - systemctl enable disk_check.service\n  - echo \"Custom cloud initialization commands completed!\" >> /var/log/cloud-init-output.log"
  }
  TEST_VM_2 = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    az_hint    = "nova:cdm-bl-pca11"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
    }


    user_data = {
      template_file = "templates/cloud-init-2.yaml"  # Путь к файлу шаблона
    }
  }
  TEST_VM_3 = {
    image_name = "ubuntu-20.04-server-cloudimg-amd64.img"
    az_hint    = "nova:cdm-bl-pca12"
    vm_qty     = 1
    flavor     = {
      vcpus = 2
      ram   = 2048
    }
    user_data = "#cloud-config\nchpasswd:\n  expire: false\n  users:\n    - name: ubuntu\n      password: \"$6$1RIJCwfWrd3WqaPd$sKcB5WNabsMQmCl3mu1JwJUsyrgNJdux5Ahj/6e1o79RRIyDwCjjEh44lqbo18T3lmOxfHuzlXpTwfvebO7S61\"\n      type: hash\nssh_pwauth: true\n\nwrite_files:\n  - path: /etc/systemd/resolved.conf\n    content: |\n      [Resolve]\n      DNS=8.8.8.8 8.8.4.4 77.88.8.8\n      FallbackDNS=1.1.1.1\n      Domains=~.\n\nruncmd:\n  - echo \"Custom cloud-init commands started executing...\" >> /var/log/cloud-init-output.log\n  - systemctl restart systemd-resolved\n  - |\n    for i in {1..6}; do\n      apt-get update && apt-get install -y iperf3 && break || sleep 10\n    done\n  - systemctl daemon-reload\n  - systemctl start disk_check.service\n  - systemctl enable disk_check.service\n  - echo \"Custom cloud initialization commands completed!\" >> /var/log/cloud-init-output.log"
  }
}

# AZs
AZs = {
}

server_groups = {}