#!/bin/bash

# The script try to rise compute service on compute node

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

#Script_dir, current folder
script_name=$(basename "$0")
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"


[[ -z $COMP_NODE_NAME ]] && COMP_NODE_NAME="$1"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $CHECK_AFTER ]] && CHECK_AFTER="true"
[[ -z $WAIT_TIME ]] && WAIT_TIME=5
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"

[[ -z "${COMP_NODE_NAME}" ]] && { echo "Compute node name required as parameter script"; exit 1; }

# Check nova srvice list
Check_nova_srvice_list () {
  echo -e "${violet}Check nova srvice list...${normal}"
  echo -e "${yellow}openstack compute service list${normal}"
  openstack compute service list | \
    sed --unbuffered \
      -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
      -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
      #-e 's/\(.*enabled | up.*\)/\o033[92m\1\o033[39m/' \
}

# Check connection to node
Check_connection_to_node () {
  if ping -c 2 $1 &> /dev/null; then
    echo -e "${green}There is a connection with $1 - success${normal}"
  else
    printf "%s\n" "${red}No connection with $1 - error!${normal}"
    echo -e "${red}The node may be turned off.${normal}\n"
  fi
}

check_and_source_openrc_file () {
#  echo "check openrc"
  if bash $utils_dir/$check_openrc_script &> /dev/null; then
#  if bash $utils_dir/$check_openrc_script 2>&1; then
    openrc_file=$(bash $utils_dir/$check_openrc_script)
    source $openrc_file
  else
    bash $utils_dir/$check_openrc_script
    exit 1
  fi
}


#check_openstack_cli
if [[ $CHECK_OPENSTACK = "true" ]]; then
  if ! bash $utils_dir/$check_openstack_cli_script; then
    exit 1
  fi
fi

check_and_source_openrc_file

echo "Trying to raise and enable nova service on $COMP_NODE_NAME..."
echo "Check connection to host: $COMP_NODE_NAME..."
connection_success=$(Check_connection_to_node $COMP_NODE_NAME)
[ "$TS_DEBUG" = true ] && echo "[DEBUG]: connection_success: $connection_success"
if [ -n "$connection_success" ]; then
  echo "Connetction to $COMP_NODE_NAME success"
#  try_to_rise="true"
  docker_nova_started=""
  docker_nova_started=$(ssh -o StrictHostKeyChecking=no ${COMP_NODE_NAME} docker ps| grep nova_compute)
  if [ -z "$docker_nova_started" ];then
    ssh -o "StrictHostKeyChecking=no" -t ${COMP_NODE_NAME} "systemctl start kolla-consul-container.service kolla-nova_compute-container.service"
    ssh -o StrictHostKeyChecking=no ${COMP_NODE_NAME} docker start consul nova_compute
  else
    ssh -o StrictHostKeyChecking=no ${COMP_NODE_NAME} docker restart consul nova_compute
  fi
  sleep $WAIT_TIME
  openstack compute service set --enable --up "${COMP_NODE_NAME}" nova-compute
else
  echo -e "${red}No connection to $COMP_NODE_NAME - fail${normal}"
  echo -e "${red}Enable nova service on $COMP_NODE_NAME - fail${normal}"
  exit 1
fi

if [ "$CHECK_AFTER" = true ]; then
    Check_nova_srvice_list
fi

