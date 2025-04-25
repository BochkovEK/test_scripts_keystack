# VMs
VMs = {
  vm1 = {
    image_name  = "ubuntu-20.04-server-cloudimg-amd64.img"
#    image_name = "test_cirros"
    flavor      = {
        vcpus = 2
        ram   = 2048
    }
    vm_qty      = 1
    user_data   = "#cloud-config\n# https://dadroit.com/yaml-to-string/\npackage_update: true\npackages:\n  - gcc\n  - iperf\n  - iperf3\nwrite_files:\n- content: |\n    #include <stdio.h>\n    #include <time.h>\n    #include <unistd.h>\n    int main(void) {\n      char date[128];\n      char hostname[1024];\n      hostname[1023] = '\\0';\n      gethostname(hostname, 1023);\n      time_t now;\n      FILE *log;\n      unsigned long fopen_error = 0;\n      unsigned long fopen_ok = 0;\n      unsigned long fclose_error = 0;\n      unsigned long fclose_ok = 0;\n      double time_spent = 0;\n      for (;;) {\n        sleep(1);\n        clock_t tic = clock();\n        time(&now);\n        strftime(date, sizeof(date), \"%Y-%m-%d %H:%M:%S\", localtime(&now));\n        log = fopen(\"data.log\", \"a\");\n        if (log == NULL) {\n          ++fopen_error;\n        } else {\n          ++fopen_ok;\n          clock_t toc = clock();\n          time_spent = (double) (toc - tic);\n          fprintf(log, \"%s %s fopen_ok %9lu fopen_error %9lu fclose_ok %9lu fclose_error %9lu fopen_time_spent %f\\n\", hostname, date, fopen_ok, fopen_error, fclose_ok, fclose_error, time_spent);\n          if (fclose(log) !=0) {\n                  ++fclose_error;\n          } else {\n                  ++fclose_ok;\n          }\n        }\n        printf(\"%s %s fopen_ok %9lu fopen_error %9lu fclose_ok %9lu fclose_error %9lu fopen_time_spent %f\\n\", hostname, date, fopen_ok, fopen_error, fclose_ok, fclose_error, time_spent);\n      }\n      return 0;\n    }\n  path: /home/ubuntu/fopen.c\nruncmd:\n  - gcc /home/ubuntu/fopen.c -o /home/ubuntu/fopen"
    az_hint     = "nova:cdm-bl-pca10"
  }
  vm22 = {
    image_name  = "ubuntu-20.04-server-cloudimg-amd64.img"
#    image_name = "test_cirros"
    flavor      = {
        vcpus = 2
        ram   = 2048
    }
    vm_qty      = 1
    user_data   = "#cloud-config\n# https://dadroit.com/yaml-to-string/\n\nwrite_files:\n- content: |\n    #include <stdio.h>\n    #include <time.h>\n    #include <unistd.h>\n    int main(void) {\n      char date[128];\n      char hostname[1024];\n      hostname[1023] = '\\0';\n      gethostname(hostname, 1023);\n      time_t now;\n      FILE *log;\n      unsigned long fopen_error = 0;\n      unsigned long fopen_ok = 0;\n      unsigned long fclose_error = 0;\n      unsigned long fclose_ok = 0;\n      double time_spent = 0;\n      for (;;) {\n        sleep(1);\n        clock_t tic = clock();\n        time(&now);\n        strftime(date, sizeof(date), \"%Y-%m-%d %H:%M:%S\", localtime(&now));\n        log = fopen(\"data.log\", \"a\");\n        if (log == NULL) {\n          ++fopen_error;\n        } else {\n          ++fopen_ok;\n          clock_t toc = clock();\n          time_spent = (double) (toc - tic);\n          fprintf(log, \"%s %s fopen_ok %9lu fopen_error %9lu fclose_ok %9lu fclose_error %9lu fopen_time_spent %f\\n\", hostname, date, fopen_ok, fopen_error, fclose_ok, fclose_error, time_spent);\n          if (fclose(log) !=0) {\n                  ++fclose_error;\n          } else {\n                  ++fclose_ok;\n          }\n        }\n        printf(\"%s %s fopen_ok %9lu fopen_error %9lu fclose_ok %9lu fclose_error %9lu fopen_time_spent %f\\n\", hostname, date, fopen_ok, fopen_error, fclose_ok, fclose_error, time_spent);\n      }\n      return 0;\n    }\n  path: /home/ubuntu/fopen.c\n#- content: |\n#      network:\n#        version: 2\n#        ethernets:\n#            enp3s0:\n#                dhcp4: true\n#                set-name: enp3s0\n#                nameservers:\n#                    addresses:\n#                    - 8.8.8.8\n#                    - 8.8.4.4\n#  path: /etc/netplan/50-cloud-init.yaml\n#  permissions: '0644'\nbootcmd:\n  - echo \"server=8.8.8.8\" >> /etc/resolv.conf\npackage_upgrade: true\npackages:\n  - gcc\n  - iperf\n  - iperf3\nruncmd:\n  - gcc /home/ubuntu/fopen.c -o /home/ubuntu/fopen"
    az_hint     = "nova:cdm-bl-pca11"
  }
  vm3 = {
    image_name  = "ubuntu-20.04-server-cloudimg-amd64.img"
#    image_name = "test_cirros"
    flavor      = {
        vcpus = 2
        ram   = 2048
    }
    vm_qty      = 1
    user_data   = "#cloud-config\n# https://dadroit.com/yaml-to-string/\npackage_update: true\npackages:\n  - gcc\n  - iperf\n  - iperf3\nwrite_files:\n- content: |\n    #include <stdio.h>\n    #include <time.h>\n    #include <unistd.h>\n    int main(void) {\n      char date[128];\n      char hostname[1024];\n      hostname[1023] = '\\0';\n      gethostname(hostname, 1023);\n      time_t now;\n      FILE *log;\n      unsigned long fopen_error = 0;\n      unsigned long fopen_ok = 0;\n      unsigned long fclose_error = 0;\n      unsigned long fclose_ok = 0;\n      double time_spent = 0;\n      for (;;) {\n        sleep(1);\n        clock_t tic = clock();\n        time(&now);\n        strftime(date, sizeof(date), \"%Y-%m-%d %H:%M:%S\", localtime(&now));\n        log = fopen(\"data.log\", \"a\");\n        if (log == NULL) {\n          ++fopen_error;\n        } else {\n          ++fopen_ok;\n          clock_t toc = clock();\n          time_spent = (double) (toc - tic);\n          fprintf(log, \"%s %s fopen_ok %9lu fopen_error %9lu fclose_ok %9lu fclose_error %9lu fopen_time_spent %f\\n\", hostname, date, fopen_ok, fopen_error, fclose_ok, fclose_error, time_spent);\n          if (fclose(log) !=0) {\n                  ++fclose_error;\n          } else {\n                  ++fclose_ok;\n          }\n        }\n        printf(\"%s %s fopen_ok %9lu fopen_error %9lu fclose_ok %9lu fclose_error %9lu fopen_time_spent %f\\n\", hostname, date, fopen_ok, fopen_error, fclose_ok, fclose_error, time_spent);\n      }\n      return 0;\n    }\n  path: /home/ubuntu/fopen.c\nruncmd:\n  - gcc /home/ubuntu/fopen.c -o /home/ubuntu/fopen"
    az_hint     = "nova:cdm-bl-pca12"
  }
}

# AZs
AZs = {
}

server_groups = {}

