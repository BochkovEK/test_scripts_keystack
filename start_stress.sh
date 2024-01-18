#!/bin/bashq!

#The cpu/ram stress test will be launched on all VMs of hypervisor
#Exapmple start command: ./stress_test_on_vms.sh -hv cmpt-1 -cpu 4

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $KEY_NAME ]] && KEY_NAME="key_test.pem"
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME="false"
[[ -z $CPUS ]] && CPUS="4"
[[ -z $RAM ]] && RAM="4"
[[ -z $TYPE_TEST ]] && TYPE_TEST="cpu"
[[ -z $PROJECT ]] && PROJECT="admin"

while [ -n "$1" ]; do
  case "$1" in
    --help) echo -E "
      -hv               <hypervisor_name>
      -tt, -type_test   <type_of_stress_test 'cpu' or 'ram'>
      -cpu              <number_cpus_for_stress>
      -ram              <gb_ram_stress>
      -key              <path_to_key>
      -p, project       <project_name>
      "
      exit 0
      break ;;
    -hv) HYPERVISOR_NAME="$2"
      echo "Found the -hv option, with parameter value $HYPERVISOR_NAME"
      shift ;;
    -cpu) CPUS="$2"
      echo "Found the -cpu option, with parameter value $CPUS"
      shift ;;
    -ram) RAM="$2"
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

    echo "Copy stress to $VM_IP..."
    scp -o StrictHostKeyChecking=no -i $KEY_NAME stress ubuntu@$VM_IP:~
    ssh -t -o StrictHostKeyChecking=no -i $KEY_NAME ubuntu@$VM_IP "chmod +x ~/stress"

    case $MODE in
        cpu)
            echo "Starting cpu stress on $VM_IP..."
            ssh -o StrictHostKeyChecking=no -i $KEY_NAME ubuntu@$VM_IP "nohup ./stress -c $CPUS > /dev/null 2>&1 &"
            ;;
        ram)
            echo "Starting ram stress on $VM_IP..."
            ssh -o StrictHostKeyChecking=no -i $KEY_NAME ubuntu@$VM_IP "nohup ./stress --vm 1 --vm-bytes '$RAM'G > /dev/null 2>&1 &"
            ;;
    esac
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
    echo -E "
Stress test: $MODE will be launched on the hypervisor ($HV_STRING) VMs
    Stress test parameters:
        Hypervisor:           $HV
        Key:                  $KEY_NAME
        Stress test type:     $MODE
        CPUs:                 $CPUS
        or
        RAM:                  $RAM
        "

    read -p "Press enter to continue"
    VMs_IPs=$(openstack server list $HV_STRING --project $PROJECT |grep ACTIVE |awk '{print $8}')
    [[ -z $VMs_IPs ]] && { echo "No instance found in the $PROJECT project"; exit 1; }
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
