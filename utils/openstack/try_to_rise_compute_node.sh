#!/bin/bash

# The script try to rise compute service on compute node
# To start, you must specify the compute node name as a parameter

#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

#Script_dir, current folder
script_name=$(basename "$0")
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir
get_nodes_list_script="get_nodes_list.sh"
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
default_docker_engine="docker"
default_ssh_user="root"


[[ -z $COMP_NODE_NAME ]] && COMP_NODE_NAME="$1"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $CHECK_AFTER ]] && CHECK_AFTER="true"
[[ -z $WAIT_TIME ]] && WAIT_TIME=5
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $DOCKER_ENGINE ]] && DOCKER_ENGINE="$default_docker_engine"
[[ -z $TRY_TO_DISABLE_MM ]] && TRY_TO_DISABLE_MM="true"

[[ -z "${COMP_NODE_NAME}" ]] && { echo "Compute node name required as parameter script"; exit 1; }


# Check openstack cli
check_openstack_cli () {
    if [[ $CHECK_OPENSTACK = "true" ]]; then
        if ! bash $utils_dir/$check_openstack_cli_script; then
          exit 1
        fi
    fi
}

# Check and source openrc
check_and_source_openrc_file () {
  #  echo "check openrc"
    if bash $utils_dir/$check_openrc_script &> /dev/null; then
  #  if bash $utils_dir/$check_openrc_script 2>&1; then
        openrc_file=$(bash $utils_dir/$check_openrc_script)
        source $openrc_file
    else
        bash $utils_dir/$check_openrc_script
        exit 1
    fi
}

# Check nova srvice list
check_nova_srvice_list () {
    echo -e "${violet}Check nova srvice list...${normal}"
    echo -e "openstack compute service list"
    openstack compute service list | \
        sed --unbuffered \
            -e 's/\(.*disabled.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*down.*\)/\o033[31m\1\o033[39m/'
}

# Function to get nodes list using external script
get_nodes_list() {
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*"

    local nodes_result=""

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
      nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" \"$*\")"
    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result: $nodes_result
    "

    # Check for errors in node list
    if [ -z "$nodes_result" ]; then
        echo -e "${red}Failed to determine node list - ERROR${normal}"
        exit 1
    elif echo "$nodes_result" | grep -q "ERROR"; then
        echo -e "${yellow}Node names could not be determined.${normal}"
        echo -e "${yellow}Try: bash $utils_dir/$get_nodes_list_script -nt all${normal}"
        echo -e "${red}Node names could not be determined - ERROR!${normal}"
        exit 1
    else
        echo "$nodes_result"
    fi
}

# Check connection to node
check_connection_to_node () {
    local node_name=$1
    local node_ip=$2

    if ping -c 2 "$node_ip" &> /dev/null; then
        echo -e "${green}There is a connection with $node_name - success${normal}"
    else
        echo -e "${red}No connection with $node_name by ip: $node_ip - ERROR!${normal}"
        echo -e "${red}The node may be turned off.${normal}\n"
    fi
}

# Try to disable MM
try_to_disable_MM () {
    local hyper_name=$1
    hyper_id=$(openstack compute service list|grep -m 1 "$hyper_name"|awk '{print $2}')
    echo "$hyper_id"

    internal_FQDN=${OS_AUTH_URL/:5000}
    echo "$internal_FQDN"

    [ "$TS_DEBUG" = true ] && echo "
    [DEBUG]
        internal_FQDN: $internal_FQDN
        login: $OS_USERNAME,
        password: $OS_PASSWORD,
        user_domain_name: $OS_USER_DOMAIN_NAME,
        project_name: $OS_PROJECT_NAME,
        project_domain_name: $OS_PROJECT_DOMAIN_NAME
    "

    TOKEN=$(curl -s -H "Content-Type: application/json" -H 'accept: application/json' -X POST $internal_FQDN:13000/login \
        -d '{
              "login": "'"$OS_USERNAME"'",
                "password": "'"$OS_PASSWORD"'",
                "user_domain_name": "'"$OS_USER_DOMAIN_NAME"'",
                "project_name": "'"$OS_PROJECT_NAME"'",
                "project_domain_name": "'"$OS_PROJECT_DOMAIN_NAME"'"
            }'| python3 -c "import sys, json; print(json.load(sys.stdin)['X-Auth-Token'])"); echo "$TOKEN"

    #maintenance #MM
    curl -i \
        -H "X-Auth-Token: $TOKEN" \
        -X PUT "$internal_FQDN":12999/api/"$OS_REGION_NAME"/hypervisors/"$hyper_id"/maintenance_mode_off

    curl -i \
        -H "X-Auth-Token: $TOKEN" \
        -X GET "$internal_FQDN":12999/api/"$OS_REGION_NAME"/hypervisors
}

# Get ssh user
get_ssh_user () {
    # Determine SSH user
    if [[ -z "$SSH_USER" ]]; then
        SSH_USER=$(whoami 2>/dev/null) || {
            echo -e "${yellow}Warning: Failed to determine user via whoami${normal}" >&2
            SSH_USER="$default_ssh_user"
        }
    fi

    # Final user validation
    if [[ -z "$SSH_USER" ]]; then
        echo -e "${red}Error: Failed to determine SSH user!${normal}" >&2
        exit 1
    fi
}

check_openstack_cli
check_and_source_openrc_file
get_ssh_user

compute_node_pair=$(get_nodes_list -nn "$COMP_NODE_NAME")
node_name="${compute_node_pair%%:*}"
node_ip="${compute_node_pair#*:}"

echo "Trying to raise and enable nova service on $node_name...
Check connection to host: $node_name by ip: $node_ip..."

connection_success=$(check_connection_to_node "$node_name" "$node_ip")

[ "$TS_DEBUG" = true ] && echo "[DEBUG]: connection_success: $connection_success"

if [ -n "$connection_success" ] && [[ "$connection_success" != *"ERROR"* ]]; then
    echo "Connection to $node_name success"
    docker_nova_started=""
    docker_nova_started=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" sudo $DOCKER_ENGINE ps| grep nova_compute)
    if [ -z "$docker_nova_started" ];then
        ssh -o StrictHostKeyChecking=no -t "$SSH_USER@$node_ip" "sudo systemctl start kolla-consul-container.service kolla-nova_compute-container.service"
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" sudo $DOCKER_ENGINE start consul nova_compute
    else
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" sudo $DOCKER_ENGINE restart consul nova_compute
    fi
    sleep $WAIT_TIME
    openstack compute service set --enable --up "${node_name}" nova-compute
else
    echo -e "${red}No connection to $node_name - fail${normal}"
    echo -e "${red}Enable nova service on $node_name - fail${normal}"
    exit 1
fi

[ "$TS_DEBUG" = true ] && echo "[DEBUG]: connection_success: $connection_success"
[ "$TRY_TO_DISABLE_MM" = true ] && try_to_disable_MM "$COMP_NODE_NAME"
[ "$CHECK_AFTER" = true ] && check_nova_srvice_list


