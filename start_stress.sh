#!/bin/bashq!

#The cpu/ram stress test will be launched on all VMs of hypervisor
#Exapmple start command: ./stress_test_on_vms.sh -hv cmpt-1 -cpu 4

key_name=key1.pem
hypervisor_name=cmpt-1
cpus='4'
ram='4'
type_test='cpu'

OPENRC_PATH="$HOME/openrc"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)


while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -hv <hypervisor_name>
        -tt <type_of_stress_test cpu or ram>
        -cpu <number_cpus_for_stress>
        -ram <gb_ram_stress>
        "
            exit 0
            break ;;
        -hv) hypervisor_name="$2"
            echo "Found the -hv option, with parameter value $hypervisor_name"
            shift ;;
        -cpu) cpus="$2"
            echo "Found the -cpu option, with parameter value $cpus"
            shift ;;
        -ram) ram_gb="$2"
            echo "Found the -ram option in Gb, with parameter value $ram_gb"
            shift;;
        -tt) type_test="$2"
            echo "Found the -tt option, with parameter value $type_test"
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
    scp -o StrictHostKeyChecking=no -i $key_name stress ubuntu@$VM_IP:~
    ssh -t -o StrictHostKeyChecking=no -i $key_name ubuntu@$VM_IP "chmod +x ~/stress"

    case $MODE in
        cpu)
            echo "Starting cpu stress on $VM_IP..."
            ssh -o StrictHostKeyChecking=no -i $key_name ubuntu@$VM_IP "nohup ./stress -c $cpus > /dev/null 2>&1 &"
            ;;
        ram)
            echo "Starting ram stress on $VM_IP..."
            ssh -o StrictHostKeyChecking=no -i $key_name ubuntu@$VM_IP "nohup ./stress --vm 1 --vm-bytes '$ram_gb'G > /dev/null 2>&1 &"
            ;;
    esac
}

batch_run_stress() {
    local MODE=$2
    VMs_IPs=$(openstack server list --host $1 |grep ACTIVE |awk '{print $8}')
    echo -E "
Stress test: $MODE will be launched on the hypervisor $1 VMs
    Stress test parameters:
        Hypervisor: $1
        Stress test type: $MODE
        CPUs: $cpus or RAM: $ram
        "

    read -p "Press enter to continue"
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
batch_run_stress $hypervisor_name $type_test
