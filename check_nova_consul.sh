#!/bin/bash

# The script determines the node for which the nova service is disabled and trying to turn it on
# This script can take the path to the "openrc" file as a parameter (./nova_up.sh /installer/config/openrc)

OPENRC_PATH="./openrc"

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

[[ ! -z "$1" ]] && OPENRC_PATH="${1}"

# functions
# Check openrc file
Check_openrc_file () {
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    [[ -z "$check_openrc_file" ]] && (echo "openrc file not found in $OPENRC_PATH"; exit 1)

    source $OPENRC_PATH
}

# Check nova srvice list
Check_nova_srvice_list () {
    echo "Check nova srvice list"
    nova_state_list=$(openstack compute service list)
    echo "$nova_state_list" | \
        sed --unbuffered \
            -e 's/\(.*enabled | up.*\)/\o033[92m\1\o033[39m/' \
            -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
    nova_nodes_list=$(echo "$nova_state_list" | grep -E "nova-compute|nova-scheduler" | awk '{print $6}')
#    echo "nova_nodes_list: $nova_nodes_list"
#    cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')
#    echo "cmpt_disabled_nova_list: $cmpt_disabled_nova_list"
}

# Check connection to nova nodes
Check_connection_to_nova_nodes () {
    echo "Check connection to nova nodes"

    for host in $nova_nodes_list;do
        host $host
        if ping -c 1 $host &> /dev/null; then
            printf "%40s\n" "${green}There is a connection with $host - success${normal}"
        else
            printf "%40s\n" "${red}No connection with $host - error!${normal}"
            unreachable_nova_node=$(host $host |grep -E "ctrl|cmpt")
            if [ ! -z "$unreachable_nova_node" ]; then
                printf "%40s\n" "${red}One of the nova cluster nodes is unreachable!${normal}"
                printf "${red}The node may be turned off.${normal}\n"
                exit 1
            fi
        fi
    done
}

# Check disabled computes in nova
Check_disabled_computes_in_nova () {
    cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')

    # Trying to raise and enable nova service on cmpt
    if [ ! -z "$cmpt_disabled_nova_list" ]; then
        for cmpt in $cmpt_disabled_nova_list; do
            echo "Trying to raise and enable nova service on $cmpt"
            openstack compute service set --enable ${cmpt} nova-compute
            openstack compute service set --up ${cmpt} nova-compute
        done
        nova_state_list=$(openstack compute service list)
        echo "$nova_state_list" | \
            sed --unbuffered \
                -e 's/\(.*enabled | up.*\)/\o033[92m\1\o033[39m/' \
                -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
                -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'

        cmpt_disabled_nova_list=$(echo "$nova_state_list" | grep -E "(nova-compute.+disable)|(nova-compute.+down)" | awk '{print $6}')
        if [ ! -z "$cmpt_disabled_nova_list" ]; then
            for cmpt in $cmpt_disabled_nova_list; do
                printf "${red}Failed to start nova service on $cmpt${normal}"
                exit 1
            done
        fi
    fi
}

# Check docker consul
Check_docker_consul () {
    echo "Check consul docker on nodes"

    for host in $nova_nodes_list;do
        echo "consul on $host"
        ssh -o StrictHostKeyChecking=no $host "docker ps | grep consul"
    done
}

# Check members list
Check_members_list () {
    ctrl_node=($nova_nodes_list)
    echo "Check members list on ${ctrl_node[0]}"
    ssh -t -o StrictHostKeyChecking=no $ctrl_node "docker exec -it consul consul members list"
}

# Check consul logs
Check_consul_logs () {
    echo "Check consul logs"
    leader_ctrl_node=$(ssh -t -o StrictHostKeyChecking=no $ctrl_node "docker exec -it consul consul operator raft list-peers" | grep leader | awk '{print $1}')
    echo "Leader consul node is $leader_ctrl_node"
    ssh -o StrictHostKeyChecking=no $leader_ctrl_node tail -7 /var/log/kolla/autoevacuate.log; DATE=$(date); printf "%40s\n" "${violet}${DATE}${normal}"
}

clear

Check_openrc_file
Check_nova_srvice_list
Check_connection_to_nova_nodes
Check_disabled_computes_in_nova
Check_docker_consul
Check_members_list
Check_consul_logs
