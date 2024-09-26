#!/bin/bash

# The script check configs by list on controls nodes and find group [castellan_configsource]

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")

command_on_nodes_script_name="command_on_nodes.sh"

config_list=(
  "/etc/kolla/keystone/keystone.conf"
  "/etc/kolla/glance-api/glance-api.conf"
  "/etc/kolla/cinder-volume/cinder.conf"
  "/etc/kolla/neutron-server/neutron.conf"
  "/etc/kolla/nova-compute/nova.conf"
  "/etc/kolla/drs/drs.ini"
)

# Check script exists
if [ ! -f $parent_dir/$command_on_nodes_script_name ]; then
  printf "%s\n" "${red}Script: $parent_dir/$command_on_nodes_script_name does not exists - error${normal}"
  exit 0
fi

for config in "${config_list[@]}"; do
  bash $parent_dir/$command_on_nodes_script_name -nt ctrl -c "cat $config"
done
