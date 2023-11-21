#!/bin/bash

# The script displays logs from the consul service
# The node from which the log is checked is determined by the NODE_NAME variable. This variable can be set as the first parameter when running the script
# The check period is determined by the OUTPUT_PERIOD variable. This variable can be set as the second parameter when running the script

LOG_LAST_LINES_NUMBER=15
OUTPUT_PERIOD=10
OPENRC_PATH=$HOME/openrc

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

[[ ! -z "${2}" ]] && OUTPUT_PERIOD=${2}

if [ -z "${1}" ]; then
    check_openrc_file=$(ls -f $OPENRC_PATH 2>/dev/null)
    [[ -z "$check_openrc_file" ]] && { echo "openrc file not found in $OPENRC_PATH"; exit 1; }

    source $OPENRC_PATH

# Check nova srvice list
    nova_state_list=$(openstack compute service list)
    nova_nodes_list=$(echo "$nova_state_list" | grep -E "nova-compute|nova-scheduler" | awk '{print $6}')
    nova_nodes_arr=($nova_nodes_list)
    ctrl_node=${nova_nodes_arr[0]}
    leader_ctrl_node=$(ssh -t -o StrictHostKeyChecking=no $ctrl_node "docker exec -it consul consul operator raft list-peers" | grep leader | awk '{print $1}')
    NODE_NAME=$leader_ctrl_node
    echo "Leader consul node is $NODE_NAME"
else
    NODE_NAME=$1
fi

clear

echo -e "Consul logs from $NODE_NAME node"
echo -e "Output period check: $OUTPUT_PERIOD sec"

while :
do
    ssh -o StrictHostKeyChecking=no $NODE_NAME tail -n $LOG_LAST_LINES_NUMBER /var/log/kolla/autoevacuate.log | \
        sed --unbuffered \
        -e 's/\(.*Starting fence.*\)/\o033[31m\1\o033[39m/' \
        -e 's/\(.*IPMI "power off".*\)/\o033[31m\1\o033[39m/'; \
        DATE=$(date); printf "${violet}${DATE}${normal}\n"
    sleep $OUTPUT_PERIOD
done
