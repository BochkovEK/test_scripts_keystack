#!/bin/bashq!

#The cpu/ram stress test will be launched on all VMs of hypervisor
#Exapmple start command: ./stress_test_on_vms.sh -hv cmpt-1 -cpu 4

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

script_dir=$(dirname $0)

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $KEY_NAME ]] && KEY_NAME="key_test.pem"
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME="false"
[[ -z $CPUS ]] && CPUS="4"
[[ -z $RAM ]] && RAM="4"
[[ -z $TIME_OUT ]] && TIME_OUT=""
[[ -z $TYPE_TEST ]] && TYPE_TEST="cpu"
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $VM_USER ]] && VM_USER="ubuntu"
[[ -z $DEBUG ]] && DEBUG="false"

#======================

while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      -hv               <hypervisor_name>
      -tt, -type_test   <type_of_stress_test 'cpu' or 'ram'>
      -cpu              <number_cpus_for_stress>
      -ram              <gb_ram_stress>
      -t, -time_out     <time_during_which_the_load_will_be_applied_in_sec>
      -key              <path_to_key>
      -p, -project      <project_name>
      -u, -vm_user      <vm_user>
      -v, -debug        enabled debug output (without parameter)
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
    -tt|-type_test) TYPE_TEST="$2"
      echo "Found the -type_test option, with parameter value $TYPE_TEST"
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
    -v|-debug) DEBUG="true"
	    echo "Found the -debug, with parameter value $DEBUG"
      ;;
    --) shift
      break ;;
    *) echo "$1 is not an option";;
  esac
  shift
done

# Functions

copy_and_stress() {
  local VM_IP=$1
  local MODE=$2

  echo -e "\nStart checking $VM_IP..."
  sleep 1
  if ping -c 2 $VM_IP &> /dev/null; then
    printf "%40s\n" "${green}There is a connection with $VM_IP - success${normal}"
    ssh -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$VM_IP "echo 2>&1"
    test $? -eq 0 && printf "%40s\n" "${green}There is a SSH connection with $VM_IP - success${normal}" || \
    { printf "%40s\n" "${red}No SSH connection with $VM_IP - error!${normal}"; return; }
  else
    printf "%40s\n" "${red}No connection with $VM_IP - error!${normal}"
    return
  fi

#  echo "Copy stress to $VM_IP..."
#  scp -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $script_dir/stress $VM_USER@$VM_IP:~
#  ssh -t -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$VM_IP "chmod +x ~/stress"
#
#  case $MODE in
#    cpu)
#      echo "Starting cpu stress on $VM_IP..."
#      ssh -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$VM_IP "nohup ./stress -c $CPUS $time_out_string > /dev/null 2>&1 &"
#      ;;
#    ram)
#      echo "Starting ram stress on $VM_IP..."
#      ssh -o StrictHostKeyChecking=no -i $script_dir/$KEY_NAME $VM_USER@$VM_IP "nohup ./stress --vm 1 --vm-bytes '$RAM'G $time_out_string > /dev/null 2>&1 &"
#      ;;
#  esac
}

batch_run_stress() {
  if [ "${1}" = false ]; then
    HV="start stress test on all VMs on project: $PROJECT"
    HV_STRING=""
  else
    HV=${1}
    HV_STRING="--host $HV"
  fi
  local MODE=$2
  # load_string
  if [ "$MODE" = cpu ]; then
    load_string="CPU:                      $CPUS"
  else
    load_string="RAM:                      $RAM"
  fi
  # time_out_help_string, time_out_string
  if [ -n "$TIME_OUT" ]; then
    time_out_help_string="time out stress loading:  $TIME_OUT"
    time_out_string="-t $TIME_OUT"
  fi
  echo -E "
Stress test: $MODE will be launched on the hypervisor ($HV_STRING) VMs
    Stress test parameters:
        Hypervisor:               $HV
        Key:                      $KEY_NAME
        Stress test type:         $MODE
        User on VM (SSH):         $VM_USER
        $load_string
        $time_out_help_string
  "

  read -p "Press enter to continue"
  VMs_IPs=$(openstack server list $HV_STRING --project $PROJECT |grep ACTIVE |awk '{print $8}')
  [[ -z $VMs_IPs ]] && { echo "No instance found in the $PROJECT project"; exit 1; }

  [ "$DEBUG" = true ] && echo -e "
  [DEBUG]: VM_IP: $VM_IP
  [DEBUG]: MODE: $MODE
  [DEBUG]: CPUS: $CPUS
  [DEBUG]: RAM: $RAM
  [DEBUG]: time_out_string: $time_out_string
  [DEBUG]: key path: $script_dir/$KEY_NAME
  [DEBUG]: VM_USER: $VM_USER
  "

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
batch_run_stress $HYPERVISOR_NAME $TYPE_TEST
