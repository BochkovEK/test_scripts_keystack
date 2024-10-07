#!/bin/bash

# The script return active VMs IPs list from host

script_dir=$(dirname $0)
utils_dir=$script_dir/utils

[[ -z $TS_DEBUG ]] && TS_DEBUG="false"

check_and_source_openrc_file () {
  echo "check openrc"
  openrc_file=$(bash $utils_dir/check_openrc.sh)
  if [[ -z $openrc_file ]]; then
    exit 1
  else
    echo $openrc_file
    source $openrc_file
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
  if [ -z $VMs_IPs ]; then
    VMs_IPs=$(openstack server list $project_string --long | \
      grep -E "ACTIVE.*$HYPERVISOR_NAME" |awk '{print $12}')
    [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: command to define vms ip list
    VMs_IPs=\$(openstack server list --project $PROJECT --long |
      grep -E "ACTIVE.*$HYPERVISOR_NAME" |awk '{print \$12}')
  [DEBUG]: VMs_IPs: $VMs_IPs
  "
    if [ -z $VMs_IPs ]; then
      echo -e "No instance found in the $PROJECT project\nProject list:"
      openstack project list
      exit 1
    fi
  fi
  echo $VMs_IPs
}

check_and_source_openrc_file
get_VMs_IPs