#!/bin/bash

# The script return active VMs IPs list from host
# WARNING: only one designated port is supported (example: pub_net)


#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

#script_name=$(basename "$0")
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"

[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
#[[ -z $UTIL_MODE ]] && UTIL_MODE="true"

check_openstack_cli () {
  if ! bash $utils_dir/$check_openstack_cli_script &> /dev/null; then
    exit 1
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

get_VMs_IPs () {
  [[ -n $PROJECT ]] && { project_string="--project $PROJECT"; }
  [[ -n $HYPERVISOR_NAME ]] && { host_string="--host $HYPERVISOR_NAME"; }
  VMs_IPs=$(openstack server list $project_string $host_string |grep ACTIVE |awk '{print $8}')
  [ "$TS_DEBUG" = true ] && echo -e "

  [DEBUG]: command to define vms ip list
    VMs_IPs=\$(openstack server list $host_string $project_string |grep ACTIVE |awk '{print \$8}')
  [DEBUG]: VMs_IPs: $VMs_IPs
  "
  # in openstack cli version 6.2 the --host key gives an empty output
  if [ -z "$VMs_IPs" ]; then
    VMs_IPs=$(openstack server list $project_string --long | \
      grep -E "ACTIVE.*$HYPERVISOR_NAME" |awk '{print $12}')
    [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: command to define vms ip list
    VMs_IPs=\$(openstack server list --project $PROJECT --long |
      grep -E "ACTIVE.*$HYPERVISOR_NAME" |awk '{print \$12}')
  [DEBUG]: VMs_IPs: $VMs_IPs
  "
    if [ -z "$VMs_IPs" ]; then
#      [ "$UTIL_MODE" = true ] && {
      echo -e "${red}No instance found in the $PROJECT project - ERROR${normal}\nProject list:";
      openstack project list;
#      }
      exit 1
    fi
  fi

  for raw_string_ip in $VMs_IPs; do
    IP="${raw_string_ip##*=}"
    echo $IP
  done
}

check_openstack_cli
check_and_source_openrc_file
get_VMs_IPs