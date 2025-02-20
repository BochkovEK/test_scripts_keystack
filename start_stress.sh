#!/bin/bash

#The cpu/ram stress test will be launched on all VMs of hypervisor
#Exapmple start command: ./stress_test_on_vms.sh -hv cmpt-1 -cpu 4

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

script_dir=$(dirname $0)
utils_dir=$script_dir/utils
openstack_utils=$utils_dir/openstack
check_vm_script="command_on_vms.sh"
get_active_vms_ips_list_script="get_active_vms_ips_list.sh"
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
#check_openrc_script="check_openrc.sh"

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $KEY_PATH ]] && KEY_PATH="$script_dir/key_test.pem"
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME=""
[[ -z $CPUS ]] && CPUS="2"
[[ -z $RAM ]] && RAM="4"
[[ -z $TIME_OUT ]] && TIME_OUT=""
[[ -z $TYPE_TEST ]] && TYPE_TEST="cpu"
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $VM_USER ]] && VM_USER="ubuntu"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $UNITS ]] && UNITS="G"
[[ -z $IP_LIST_FILE ]] && IP_LIST_FILE=""
[[ -z $VMs_IPs ]] && VMs_IPs=""
#======================

while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
    !!! WARNING: Cirros OS doesn't work with binary ./stress

      -hv               <hypervisor_name> (WARNING: doesn't work with version openstack cli 6.2.0)
      -cpu              <number_cpus_for_stress>
      -ram              <gb_ram_stress>
      -units            <units for RAM stress: B,K,M,G (size). \"G - default\">
      -t, -time_out     <time_during_which_the_load_will_be_applied_in_sec>
      -key              <path_to_key>
      -p, -project      <project_name>
      -u, -vm_user      <vm_user>
      -v, -debug        enabled debug output (without parameter)
      -ip_list_file          <path_to_file> with VMs IP list
                        Example: (cat ./ip_list_file)
                          10.224.132.179
                          10.224.132.175
                          10.224.132.188
      -ips              <ips list> (example: -ips \"<ip_vm_1> <ip_vm_2> ... \")
      "
      exit 0
      break ;;
    -hv) HYPERVISOR_NAME="$2"
      echo "Found the -hv option, with parameter value $HYPERVISOR_NAME"
      shift ;;
    -cpu) CPUS="$2"; TYPE_TEST="cpu"
      echo "Found the -cpu option, with parameter value $CPUS"
      shift ;;
    -ram) RAM="$2"; TYPE_TEST="ram"
      echo "Found the -ram option in Gb, with parameter value $RAM"
      shift;;
    -units) UNITS="$2"
      echo "Found the -units option with parameter value $UNITS"
      shift;;
    -key) KEY_PATH="$2"
      echo "Found the -key option, with parameter value : $KEY_PATH"
      shift;;
    -p|-project) PROJECT="$2"
      echo "Found the -project option, with parameter value $PROJECT"
      shift;;
    -u|-vm_user) VM_USER="$2"
      echo "Found the -vm_user option, with parameter value $VM_USER"
      shift;;
    -t|-time_out) TIME_OUT="$2"
      echo "Found the -time_out option, with parameter value $TIME_OUT"
      shift;;
    -v|-debug) TS_DEBUG="true"
	    echo "Found the -debug, with parameter value $TS_DEBUG"
      ;;
    -ip_list_file) IP_LIST_FILE="$2"
      echo "Found the -ip_list option, with parameter value $IP_LIST_FILE"
      shift;;
    -ips) VMs_IPs="$2"
      echo "Found the -ips option, with parameter value $VMs_IPs"
      shift ;;
    --) shift
      break ;;
    *) echo "$1 is not an option";;
  esac
  shift
done

# Functions
copy_and_stress() {
  local VM_IP=$1
#  local MODE=$2

#  echo -e "\nStart checking $VM_IP..."
#  sleep 1
#  if ping -c 2 $VM_IP &> /dev/null; then
#    printf "%40s\n" "${green}There is a connection with $VM_IP - success${normal}"
#    ssh -o StrictHostKeyChecking=no -i $script_dir/$KEY_PATH $VM_USER@$VM_IP "echo 2>&1"
#    test $? -eq 0 && printf "%40s\n" "${green}There is a SSH connection with $VM_IP - success${normal}" || \
#    { printf "%40s\n" "${red}No SSH connection with $VM_IP - error!${normal}"; exit 1; }
#  else
#    printf "%40s\n" "${red}No connection with $VM_IP - error!${normal}"
#    exit 1
##    return
#  fi

  echo "Copy stress to $VM_IP..."
  scp -o StrictHostKeyChecking=no -i $KEY_PATH $script_dir/stress $VM_USER@$VM_IP:~
  ssh -t -o StrictHostKeyChecking=no -i $KEY_PATH $VM_USER@$VM_IP "chmod +x ~/stress"

  case $TYPE_TEST in
    cpu)
      echo "Starting cpu stress on $VM_IP..."
      ssh -o StrictHostKeyChecking=no -i $KEY_PATH $VM_USER@$VM_IP "nohup ./stress -c $CPUS $time_out_string > /dev/null 2>&1 &"
      ;;
    ram)
      echo "Starting ram stress on $VM_IP..."
      ssh -o StrictHostKeyChecking=no -i $KEY_PATH $VM_USER@$VM_IP "nohup ./stress --vm 1 --vm-bytes '$RAM'$UNITS $time_out_string > /dev/null 2>&1 &"
      ;;
  esac
}

check_vm () {
  if [ -f $script_dir/$check_vm_script ]; then
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]:
    HYPERVISOR_NAME: $HYPERVISOR_NAME
    PROJECT: $PROJECT
    VMs_IPs: $VMs_IPs
    VM_USER: $VM_USER
    KEY_PATH: $KEY_PATH
"
  export HYPERVISOR_NAME=$HYPERVISOR_NAME
  export PROJECT=$PROJECT
  export VMs_IPs=$VMs_IPs
  export VM_USER=$VM_USER
  export KEY_PATH=$KEY_PATH
  export ONLY_CHECK=true
  [ "$TS_DEBUG" = true ] && { debug_string="-v"; }
  if ! bash $script_dir/$check_vm_script $debug_string; then
    echo -E "${red}VMs are not ready to start stress - error${normal}"
    exit 1
  fi
else
  echo -E "${red}Script $script_dir/$check_vm_script not found - error${normal}"
fi
}

get_VMs_IPs () {
  if [ -z $VMs_IPs ]; then
    if [ -z $IP_LIST_FILE ]; then
      if [ -z $HYPERVISOR_NAME ]; then
        hv="all VMs on project: $PROJECT"
        host_string=""
      else
        hv="all VMs on hypervisor $HYPERVISOR_NAME"
        host_string="--host $hv"
      fi
  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]:
    HYPERVISOR_NAME: $HYPERVISOR_NAME
    PROJECT: $PROJECT
"
#
      export HYPERVISOR_NAME=$HYPERVISOR_NAME
      export PROJECT=$PROJECT
      VMs_IPs=$(bash $openstack_utils/$get_active_vms_ips_list_script)
      if echo $VMs_IPs| grep "ERROR"; then
        exit 1
      fi
    else
      VMs_IPs=$(cat $IP_LIST_FILE)
      hv="VMs list: $VMs_IPs"
    fi
  else
    hv="VMs list: $VMs_IPs"
  fi

  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]:
    hv: $hv
    host_string: $host_string
    VMs_IPs: $VMs_IPs
  "

  [[ -z $VMs_IPs ]] && { echo -e "${red}No instance found in the $PROJECT project - ERROR${normal}"; exit 1; }
}

get_mode_string () {
#  local MODE=$1
  # load_string
  if [ "$TYPE_TEST" = cpu ]; then
    load_string="CPU:                      $CPUS"
  elif [ "$TYPE_TEST" = ram ]; then
    load_string="RAM:                      $RAM; $UNITS"
  else
    echo -e "${red}Test type $TYPE_TEST not supported${normal}"
    exit 1
  fi
  # time_out_help_string, time_out_string
  if [ -n "$TIME_OUT" ]; then
    time_out_help_string="time out stress loading:  $TIME_OUT"
    time_out_string="-t $TIME_OUT"
  fi

  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: TYPE_TEST: $TYPE_TEST
  [DEBUG]: CPUS: $CPUS
  [DEBUG]: RAM: $RAM
  [DEBUG]: time_out_string: $time_out_string
  "
}

batch_run_stress () {
#Stress test: $TYPE_TEST will be launched on the hypervisor ($HV_STRING) VMs
  echo -E "
Stress test parameters:
    Start stress test on:     $hv
    Key:                      $KEY_PATH
    User on VM (SSH):         $VM_USER
    Stress test type:         $TYPE_TEST
    VMs IPs list file:        $IP_LIST_FILE
    Debug:                    $TS_DEBUG
    $load_string
    $time_out_help_string
"

  read -p "Press enter to continue: "

  for IP in $VMs_IPs; do
    copy_and_stress $IP $MODE
  done
}

#check_and_source_openrc_file () {
#  echo "check openrc"
#  openrc_file=$(bash $utils_dir/$check_openrc_script)
#  if [[ -z $openrc_file ]]; then
#    exit 1
#  else
#    echo "openrc_file: $openrc_file"
#    source $openrc_file
#  fi
#}

rm -rf /root/.ssh/known_hosts
#check_and_source_openrc_file
get_VMs_IPs
get_mode_string
check_vm
batch_run_stress

