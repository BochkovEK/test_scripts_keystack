#!/bin/bashq!

# !!! Сделать претест по пингу (тестить)
# The script checks access to the VM on HV

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

script_dir=$(dirname $0)

[[ -z $KEY_NAME ]] && KEY_NAME="key_test.pem"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME=""
[[ -z $ONLY_PING ]] && ONLY_PING="false"
[[ -z $VM_USER ]] && VM_USER="ubuntu"
[[ -z $COMMAND_STR ]] && COMMAND_STR="ls -la"
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $DONT_ASK ]] && DONT_ASK="true"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"

# Functions

batch_run_command() {
    [[ -f "$HOME/.ssh/known_hosts" ]] && { rm ~/.ssh/known_hosts; }
    host_string=""
    [[ -n ${HYPERVISOR_NAME} ]] && { host_string="--host $HYPERVISOR_NAME"; }
    echo -E "
    Start check VMs with parameters:
        Hypervisor:   $HYPERVISOR_NAME
        Key:          $KEY_NAME
        User name:    $VM_USER
        Command:      $COMMAND_STR
        Only ping:    $ONLY_PING
        Project:      $PROJECT
        "

    [[ ! $DONT_ASK = "true" ]] && { read -p "Press enter to continue"; }

    echo "Start checking..."
    VMs_IPs=$(openstack server list --project $PROJECT $host_string |grep ACTIVE |awk '{print $8}')
    [[ -z $VMs_IPs ]] && { $VMs_IPs=$(openstack server list --project $PROJECT --long | \
      grep -E "ACTIVE.*$HYPERVISOR_NAME" |awk '{print $12}'; }
    [[ -z $VMs_IPs ]] && { echo -e "No instance found in the $PROJECT project\nProject list:"; openstack project list; exit 1; }
    at_least_one_vm_is_not_avail="false"
     "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]: VMs_IPs: $VMs_IPs
    "
    for raw_string_ip in $VMs_IPs; do
        FIRST_IP=$(echo "${raw_string_ip%%,*}")
#        FIRST_IP=$(echo $raw_string_ip|awk '{print $1}')
        IP="${FIRST_IP##*=}"
        sleep 1
        if ping -c 2 $IP &> /dev/null; then
            printf "%40s\n" "${green}There is a connection with $IP - success${normal}"
            [ "$ONLY_PING" == "false" ] && { ssh -t -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$IP "$COMMAND_STR"; }
        else
            printf "%40s\n" "${red}No connection with $IP - error!${normal}"
            at_least_one_vm_is_not_avail="true"
        fi
    done
}

# Check openrc file
check_openrc_file () {
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    [[ -z "$check_openrc_file" ]] && (echo "openrc file not found in $OPENRC_PATH"; exit 1)

    source $OPENRC_PATH
}

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
    *) echo "$1 is not an option";;
  esac
  shift
done

#rm -rf /root/.ssh/known_hosts
check_openrc_file
batch_run_command
if [ "$at_least_one_vm_is_not_avail" = true ]; then
  exit 1
fi