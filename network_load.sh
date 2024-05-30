#!/bin/bash

# to start load
# ./network_load.sh --hypervisor_name mitya-keystack-comp-01 --load on
# ./network_load.sh --hypervisor_name mitya-keystack-comp-01
# to stop load
# ./network_load.sh --hypervisor_name mitya-keystack-comp-01 --load off

#key_name=key1.pem
#hypervisor_name=cmpt-1
#load="on"
#OPENRC_PATH="./openrc"


[[ -z $OPENRC_PATH ]] && OPENRC_PATH=$HOME/openrc
[[ -z $KEY_NAME ]] && KEY_NAME="key_test"
[[ -z $HYPERVISOR_HOSTNAME ]] && HYPERVISOR_HOSTNAME=""
[[ -z $LOAD ]] && LOAD="on"

network_stress() {
    local VM_IP=$1
#    local LOAD=$2

    case $LOAD in
        on)
            echo "Starting network load on $VM_IP..."
            ssh -t -o StrictHostKeyChecking=no -i $key_name ubuntu@"$VM_IP" "sudo sh -c 'echo \"@reboot root ping -f -s 1024 8.8.8.8\" >> /etc/crontab && reboot'"
            ;;
        off)
            echo "Stopping network load on $VM_IP..."
            ssh -t -o StrictHostKeyChecking=no -i $key_name ubuntu@"$VM_IP" "sudo sh -c 'sed -i '/ping/d' /etc/crontab && reboot'"
            ;;
        *) echo "load equals invalid value: $LOAD";;
    esac

}

batch_run_stress() {
    VMs_IPs=$(openstack server list --host "$1" |grep ACTIVE |awk '{print $8}')
    echo -E "
Network load will be $2 for hypervisor $1
"
    echo -E "
VMs on hypervisor $1:
$VMs_IPs
"
    read -r -p "Press enter to continue"
    for raw_string_ip in $VMs_IPs; do
        IP="${raw_string_ip##*=}"
        network_stress "$IP"
    done
}

# Check openrc file
check_openrc_file () {
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    [[ -z "$check_openrc_file" ]] && (echo "openrc file not found in $OPENRC_PATH"; exit 1)

    source $OPENRC_PATH
}

while [ -n "$1" ]
do
    case "$1" in
        --help) echo -E "
        -hypervisor_name, -hv    <hypervisor_name>
        -load, l                 <on or off>
        "
            exit 0
            break ;;
        -hypervisor_name|-hv) HYPERVISOR_HOSTNAME="$2"
            echo "hypervisor_name equals $HYPERVISOR_HOSTNAME"
            shift ;;
        -load|-l) LOAD="$2"
            echo "load equals $LOAD"
            shift ;;
        *) echo "$1 is not an option";;
        esac
        shift
done

rm -rf ~/.ssh/known_hosts
check_openrc_file
batch_run_stress "$HYPERVISOR_HOSTNAME" "$LOAD"