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
    user_data = "#cloud-config\nchpasswd:\n  expire: false\n  users:\n    - name: ubuntu\n      password: \"$6$1RIJCwfWrd3WqaPd$sKcB5WNabsMQmCl3mu1JwJUsyrgNJdux5Ahj/6e1o79RRIyDwCjjEh44lqbo18T3lmOxfHuzlXpTwfvebO7S61\"\n      type: hash\nssh_pwauth: true\n\nwrite_files:\n  - path: /etc/systemd/resolved.conf\n    content: |\n      [Resolve]\n      DNS=8.8.8.8 8.8.4.4 77.88.8.8 127.0.0.53\n      FallbackDNS=1.1.1.1\n      Domains=~.\n  # 1. Create systemd service file\n  - path: /etc/systemd/system/disk_check.service\n    content: |\n      [Unit]\n      Description=Continuous disk health monitoring via fio\n      After=network.target\n\n      [Service]\n      Type=simple\n      ExecStart=/usr/local/bin/disk_check.sh\n      Restart=always\n      StandardOutput=syslog\n      StandardError=syslog\n      SyslogIdentifier=disk_check\n\n      [Install]\n      WantedBy=multi-user.target\n    permissions: '0644'\n\n  # 2. Create monitoring script\n  - path: /usr/local/bin/disk_check.sh\n    content: |\n      #!/bin/bash\n\n      # Configuration\n      LOG_FILE=\"/var/log/disk_check.log\"\n      DISK=\"/dev/vda\"\n      TEST_DURATION=\"1s\"\n      CHECK_INTERVAL=\"10\"\n\n      while true; do\n          TIMESTAMP=$(date +\"%Y-%m-%d %T\")\n          \n          if ! fio --name=healthcheck \\\n                   --filename=$DISK \\\n                   --rw=randread \\\n                   --bs=4k \\\n                   --runtime=$TEST_DURATION \\\n                   --time_based \\\n                   --direct=1 \\\n                   --output-format=json > /tmp/fio_last_test.json 2>&1; then\n              echo \"[$TIMESTAMP] ERROR: Disk $DISK failed!\" >> $LOG_FILE\n              logger -t disk_check \"CRITICAL: Disk $DISK is unavailable!\"\n          else\n              LATENCY=$(jq '.jobs[0].read.lat_ns.mean' /tmp/fio_last_test.json 2>/dev/null)\n              echo \"[$TIMESTAMP] OK: Disk $DISK latency: $LATENCY ns\" >> $LOG_FILE\n          fi\n          \n          sleep $CHECK_INTERVAL\n      done\n    permissions: '0755'\n    owner: root:root\n\nruncmd:\n  - echo \"Custom cloud-init commands started executing...\" >> /var/log/cloud-init-output.log\n  - systemctl restart systemd-resolved\n  - |\n    for i in {1..6}; do\n      apt-get update && apt-get install -y fio jq iperf3 && break || sleep 10\n    done\n  - systemctl daemon-reload\n  - systemctl start disk_check.service\n  - systemctl enable disk_check.service\n  - echo -e \"------------------------------------\\nServer listening on 5201\\n------------------------------------\" > /var/log/iperf3_port_1.log\n  - iperf3 -s -p 5201 --daemon --logfile --debug /var/log/iperf3_port_1.log\"\n  - echo -e \"------------------------------------\\nServer listening on 5202\\n------------------------------------\" > /var/log/iperf3_port_2.log\n  - iperf3 -s -p 5202 --daemon --logfile --debug /var/log/iperf3_port_2.log\"\n  - echo \"Custom cloud initialization commands completed!\" >> /var/log/cloud-init-output.log"
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