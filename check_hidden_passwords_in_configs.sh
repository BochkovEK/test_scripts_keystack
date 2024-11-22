#!/bin/bash

# The script check configs by list on controls nodes and find group [castellan_configsource]

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 13)
cyan=$(tput setaf 14)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
#magenta=$(tput setaf 5)

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")

command_on_nodes_script_name="command_on_nodes.sh"

control_config_list=(
  "/etc/kolla/keystone/keystone.conf"
  "/etc/kolla/glance-api/glance-api.conf"
  "/etc/kolla/cinder-volume/cinder.conf"
  "/etc/kolla/neutron-server/neutron.conf"
  "/etc/kolla/drs/drs.ini"
  "/etc/kolla/placement-api/placement.conf"
  "/etc/kolla/adminui-backend/adminui-backend-osloconf.conf"
)

compute_config_list=(
  "/etc/kolla/nova-compute/nova.conf"
)

hashed_password_config_list=(
  "/etc/kolla/haproxy/services.d/opensearch-dashboards.cfg"
  "/etc/kolla/rabbitmq/definitions.json"
  "/etc/kolla/proxysql/users/*"
  "/etc/kolla/haproxy/services.d/prometheus-alertmanager.cfg"
)

prometheus_exporters_config_list=(
  "/etc/kolla/prometheus-mysqld-exporter/my.cnf"
  "/etc/kolla/prometheus-rabbitmq-exporter/prometheus-rabbitmq-config.json"
  "/etc/kolla/prometheus-openstack-exporter/clouds.yml"
)

# Check script exists
if [ ! -f $command_on_nodes_script_name ]; then
  printf "%s\n" "${red}Script: $command_on_nodes_script_name does not exists - error${normal}"
  exit 0
fi

read_conf () {
  bash $command_on_nodes_script_name -nt $1 -c "cat $2 | grep -E 'password|\[castellan_configsource\]'| \
    sed --unbuffered \
      -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1 - ok\o033[39m/' \
      -e 's/\(.*\No such file or directory.*\)/\o033[31m\1 - ok\o033[39m/'"
}

Check_configs_on_controls () {
  echo -E "${yellow}Check '[castellan_configsource]' in configs on control${normal}"
  for config in "${control_config_list[@]}"; do
    echo -E "${violet}Check control config: $config${normal}"
    read_conf ctrl $config
#    bash $command_on_nodes_script_name -nt ctrl -c "cat $config | grep -E 'password|\[castellan_configsource\]'| \
#          sed --unbuffered \
#            -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1 - ok\o033[39m/' \
#            -e 's/\(.*\No such file or directory.*\")/\o033[31m\1 - ok\o033[39m/'"
  done
}

Check_configs_on_computes () {
  echo -E "${yellow}Check '[castellan_configsource]' in configs on computes${normal}"
  for config in "${compute_config_list[@]}"; do
    echo -E "${violet}Check computes config: $config${normal}"
    read_conf comp $config
#    bash $command_on_nodes_script_name -nt comp -c "cat $config | grep '\[castellan_configsource\]'| \
#          sed --unbuffered \
#            -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1 - ok\o033[39m/' \
#            -e 's/\(.*\No such file or directory.*\")/\o033[31m\1 - ok\o033[39m/'"
  done
}

Check_config_with_hashed_password () {
  echo -E "${yellow}Check config with hashed password${normal}"
  for config in "${hashed_password_config_list[@]}"; do
    echo -E "${violet}Check control config: $config${normal}"
    bash $command_on_nodes_script_name -nt ctrl -c "cat $config | grep 'password'"
  done
}

Check_hidden_passwords_in_prometheus_exporters () {
  echo -E "${yellow}Check hidden passwords in prometheus exporters${normal}"
  for config in "${prometheus_exporters_config_list[@]}"; do
    echo -E "${violet}Check control config: $config${normal}"
    bash $command_on_nodes_script_name -nt ctrl -c "cat $config"
    # | grep 'password'"
  done
}

Check_hidden_passwords_in_prometheus_exporters
Check_configs_on_controls
Check_configs_on_computes
Check_config_with_hashed_password
