#!/bin/bashq!

# The script checks access to the VM on HV

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

script_name=$(basename "$0")
script_dir=$(dirname $0)
utils_dir=$script_dir/utils
openstack_utils=$utils_dir/openstack
check_openrc_script="check_openrc.sh"
get_active_vms_ips_list_script="get_active_vms_ips_list.sh"

[[ -z $KEY_NAME ]] && KEY_NAME="key_test.pem"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME=""
[[ -z $ONLY_PING ]] && ONLY_PING="false"
[[ -z $VM_USER ]] && VM_USER="ubuntu"
[[ -z $COMMAND_STR ]] && COMMAND_STR="ls -la"
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $DONT_ASK ]] && DONT_ASK="true"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $VMs_IPs ]] && VMs_IPs=""
#[[ -z $MODULE_MODE ]] && MODULE_MODE="false"


while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      -hv           <hypervisor_name>
      -u, -user     <user_name_on_VM_OS>
      -c, command   <command_on_VM>
      -k, -key      <key_pair_private_part_file>
      -ping         only ping check
      -p, project   <project_name>
      -dont_ask     all actions will be performed automatically (without value)
      -ips          <ips list> (example: -ips \"<ip_vm_1> <ip_vm_2> ... \")
      -v, -debug        enabled debug output (without parameter)
      "
      exit 0
      break ;;
    -hv) HYPERVISOR_NAME="$2"
      echo "Found the -hv option, with parameter value $HYPERVISOR_NAME"
      shift ;;
    -u|-user) VM_USER="$2"
      echo "Found the -user option, with parameter value $VM_USER"
      shift ;;
    -c|-command) COMMAND_STR="$2"
      echo "Found the -command option, with parameter value $COMMAND_STR"
      shift ;;
    -k|-key) KEY_NAME="$2"
	    echo "Found the -key option, with parameter value $KEY_NAME"
      shift ;;
    -p|-project) PROJECT="$2"
      echo "Found the -project option, with parameter value $PROJECT"
      shift ;;
    -ping) ONLY_PING="true"
	    echo "Found the -ping option, only ping checking";;
    --) shift
      break ;;
    -dont_ask) DONT_ASK=true
      echo "Found the -dont_ask. All actions will be performed automatically"
      ;;
    -v|-debug) TS_DEBUG="true"
	    echo "Found the -debug, with parameter value $TS_DEBUG"
      ;;
    -ips) VMs_IPs="$2"
      echo "Found the -ips option, with parameter value $VMs_IPs"
      shift ;;
    *) echo "$1 is not an option";;
  esac
  shift
done

batch_run_command() {
  [[ -f "$HOME/.ssh/known_hosts" ]] && { rm ~/.ssh/known_hosts; }
#    host_string=""
#    [[ -n ${HYPERVISOR_NAME} ]] && { host_string="--host $HYPERVISOR_NAME"; }
#    echo -E "
#Start check VMs with parameters:
#  Hypervisor:   $HYPERVISOR_NAME
#  Key:          $KEY_NAME
#  User name:    $VM_USER
#  Command:      $COMMAND_STR
#  Only ping:    $ONLY_PING
#  Project:      $PROJECT
#"

  [[ ! $DONT_ASK = "true" ]] && { read -p "Press enter to continue"; }

  echo "Start $script_name script..."
  if [ -z $VMs_IPs ]; then
#      VMs_IPs=$(openstack server list --project $PROJECT $host_string |grep ACTIVE |awk '{print $8}')
#      [ "$TS_DEBUG" = true ] && echo -e "
#      command to define vms ip list
#      VMs_IPs=\$(openstack server list $HV_STRING --project $PROJECT |grep ACTIVE |awk '{print \$8}')
#      VMs_IPs: $VMs_IPs
#      "
#      if [ -z $VMs_IPs ]; then
#        VMs_IPs=$(openstack server list --project $PROJECT --long |
#          grep -E "ACTIVE.*$HYPERVISOR_NAME" |awk '{print $12}')
#        # in openstack cli version 6.2 the --host key gives an empty output
#        if [ -z $VMs_IPs ]; then
#          echo -e "No instance found in the $PROJECT project\nProject list:"
#          openstack project list
#          exit 1
#        fi
#      fi
    export HYPERVISOR_NAME=$HYPERVISOR_NAME
    export PROJECT=$PROJECT
    VMs_IPs=$(bash $openstack_utils/$get_active_vms_ips_list_script)
  fi
  at_least_one_vm_is_not_avail="false"
   "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: VMs_IPs: $VMs_IPs
  "
  for IP in $VMs_IPs; do
#    FIRST_IP=$(echo "${raw_string_ip%%,*}")
#        FIRST_IP=$(echo $raw_string_ip|awk '{print $1}')
#    IP="${FIRST_IP##*=}"
    if ping -c 2 $IP &> /dev/null; then
        printf "%40s\n" "${green}There is a connection with $IP - success${normal}"
        [ "$ONLY_PING" == "false" ] && { ssh -t -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$IP "$COMMAND_STR"; }
    else
        printf "%40s\n" "${red}No connection with $IP - error!${normal}"
        at_least_one_vm_is_not_avail="true"
    fi
    sleep 1
  done
}

# Check openrc file
check_and_source_openrc_file () {
  echo "check openrc"
  openrc_file=$(bash $utils_dir/$check_openrc_script)
  if [[ -z $openrc_file ]]; then
    exit 1
  else
    echo $openrc_file
    source $openrc_file
  fi
}

#rm -rf /root/.ssh/known_hosts
check_and_source_openrc_file
batch_run_command
if [ "$at_least_one_vm_is_not_avail" = true ]; then
  exit 1
fi