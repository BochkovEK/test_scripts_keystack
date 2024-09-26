#!/bin/bash

# The script check configs by list on controls nodes and find group [castellan_configsource]

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

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
#  "/etc/kolla/glance-api/glance-api.conf"
#  "/etc/kolla/cinder-volume/cinder.conf"
#  "/etc/kolla/neutron-server/neutron.conf"
#  "/etc/kolla/drs/drs.ini"
#  "/etc/kolla/placement-api/placement.conf"
#  "/etc/kolla/adminui-backend/adminui-backend-osloconf.conf"
)

compute_config_list=(
  "/etc/kolla/nova-compute/nova.conf"
)

# Check script exists
if [ ! -f $parent_dir/$command_on_nodes_script_name ]; then
  printf "%s\n" "${red}Script: $parent_dir/$command_on_nodes_script_name does not exists - error${normal}"
  exit 0
fi

for config in "${control_config_list[@]}"; do
  echo -E "${yellow}Check control config: $config${normal}"
  bash $parent_dir/$command_on_nodes_script_name -nt ctrl -c "cat $config"| grep '[castellan_configsource]'| \
        sed --unbuffered \
          -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1 - ok\o033[39m/'
#done
#for config in "${compute_config_list[@]}"; do
#  echo -E "${yellow}Check compute config: $config${normal}"
#    bash $parent_dir/$command_on_nodes_script_name -nt comp -c "cat $config"| \
#        sed --unbuffered \
#          -e 's/\(.*\[castellan_configsource\].*\)/\o033[32m\1\o033[39m/'
done
