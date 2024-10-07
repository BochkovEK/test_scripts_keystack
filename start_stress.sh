#!/bin/bash

#The cpu/ram stress test will be launched on all VMs of hypervisor
#Exapmple start command: ./stress_test_on_vms.sh -hv cmpt-1 -cpu 4

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

script_dir=$(dirname $0)
check_vm_script="check_vm.sh"

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $KEY_NAME ]] && KEY_NAME="key_test.pem"
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME="false"
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
    !!! WARNING: Before running the script, make sure the VM is available:
       bash ~/test_scripts_keystack/check_vm.sh --help
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
      -ip_list          <path_to_file> with VMs IP list
                        Example: (cat ./ip_list_file)
                          10.224.132.179
                          10.224.132.175
                          10.224.132.188
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
    -key) KEY_NAME="$2"
      echo "Found the -key option, with parameter value key name: $KEY_NAME"
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
    -ip_list) IP_LIST_FILE="$2"
      echo "Found the -ip_list option, with parameter value $IP_LIST_FILE"
      shift;;
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

  echo -e "\nStart checking $VM_IP..."
  sleep 1
  if ping -c 2 $VM_IP &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $VM_IP - success${normal}"
    ssh -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$VM_IP "echo 2>&1"
    test $? -eq 0 && printf "%40s\n" "${green}There is a SSH connection with $VM_IP - success${normal}" || \
    { printf "%40s\n" "${red}No SSH connection with $VM_IP - error!${normal}"; exit 1; }
  else
    printf "%40s\n" "${red}No connection with $VM_IP - error!${normal}"
    exit 1
#    return
  fi

  echo "Copy stress to $VM_IP..."
  scp -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $script_dir/stress $VM_USER@$VM_IP:~
  ssh -t -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$VM_IP "chmod +x ~/stress"

  case $TYPE_TEST in
    cpu)
      echo "Starting cpu stress on $VM_IP..."
      ssh -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$VM_IP "nohup ./stress -c $CPUS $time_out_string > /dev/null 2>&1 &"
      ;;
    ram)
      echo "Starting ram stress on $VM_IP..."
      ssh -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$VM_IP "nohup ./stress --vm 1 --vm-bytes '$RAM'$UNITS $time_out_string > /dev/null 2>&1 &"
      ;;
  esac
}

check_vm () {
  if [ -f $script_dir/$check_vm_script ]; then
  export HYPERVISOR_NAME=$HYPERVISOR_NAME
  export TS_DEBUG=$TS_DEBUG
  if ! bash $script_dir/$check_vm_script; then
    echo -E "${red}VMs are not ready to start stress - error${normal}"
    exit 1
  fi
else
  echo -E "${red}Script $script_dir/$check_vm_script not found - error${normal}"
fi
}

get_VMs_IPs () {
  if [ -z $HYPERVISOR_NAME ]; then
    hv="start stress test on all VMs on project: $PROJECT"
    host_string=""
  else
    hv=$HYPERVISOR_NAME
    host_string="--host $HV"
  fi

  if [ -z $VMs_IPs ]; then
    if [ -z $IP_LIST_FILE ]; then
      VMs_IPs=$(openstack server list --project $PROJECT $host_string |grep ACTIVE |awk '{print $8}')
      [ "$TS_DEBUG" = true ] && echo -e "
      command to define vms ip list
      VMs_IPs=\$(openstack server list $host_string --project $PROJECT |grep ACTIVE |awk '{print \$8}')
      VMs_IPs: $VMs_IPs
      "
      # in openstack cli version 6.2 the --host key gives an empty output
      if [ -z $VMs_IPs ]; then
        VMs_IPs=$(openstack server list --project $PROJECT --long |
          grep -E "ACTIVE.*$HYPERVISOR_NAME" |awk '{print $12}')
        [ "$TS_DEBUG" = true ] && echo -e "
      command to define vms ip list
      VMs_IPs=\$(openstack server list --project $PROJECT --long |
          grep -E "ACTIVE.*$HYPERVISOR_NAME" |awk '{print \$12}')
      VMs_IPs: $VMs_IPs
      "
        if [ -z $VMs_IPs ]; then
          echo -e "No instance found in the $PROJECT project\nProject list:"
          openstack project list
          exit 1
        fi
      fi

    else
      VMs_IPs=$(cat $IP_LIST_FILE)
    fi
  fi

  [ "$TS_DEBUG" = true ] && echo -e "
  [DEBUG]: hv: $hv
  [DEBUG]: host_string: $host_string
  [DEBUG]: VMs_IPs: $VMs_IPs
  "

  [[ -z $VMs_IPs ]] && { echo "No instance found in the $PROJECT project"; exit 1; }
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
  echo -E "
Stress test: $MODE will be launched on the hypervisor ($HV_STRING) VMs
    Stress test parameters:
        Hypervisor:               $HV
        Key:                      $KEY_NAME
        User on VM (SSH):         $VM_USER
        Stress test type:         $MODE
        VMs IPs list file:        $IP_LIST_FILE
        Debug:                    $TS_DEBUG
        $load_string
        $time_out_help_string
  "

  read -p "Press enter to continue:"

  for raw_string_ip in $VMs_IPs; do
    IP="${raw_string_ip##*=}"
    copy_and_stress $IP $MODE
  done
}

# Check openrc file
check_openrc_file () {
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    [[ -z "$check_openrc_file" ]] && (echo "openrc file not found in $OPENRC_PATH"; exit 1)

    source $OPENRC_PATH
}

rm -rf /root/.ssh/known_hosts
check_openrc_file
get_VMs_IPs
get_mode_string
check_vm
batch_run_stress

