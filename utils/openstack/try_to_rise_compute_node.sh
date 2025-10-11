#!/bin/bash

# The script try to rise compute service on compute node
# To start, you must specify the compute node name as a parameter

# Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)

# Script_dir, current folder
script_name=$(basename "$0")
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir
get_nodes_list_script="get_nodes_list.sh"
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
get_ssh_user_script="get_ssh_user.sh"
default_docker_engine="docker"
default_ssh_user="root"

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
)

# Default values
[[ -z $COMP_NODE_NAME ]] && COMP_NODE_NAME="$1"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $CHECK_AFTER ]] && CHECK_AFTER="true"
[[ -z $WAIT_TIME ]] && WAIT_TIME=5
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $CONTAINER_ENGINE ]] && CONTAINER_ENGINE="$default_docker_engine"
[[ -z $TRY_TO_DISABLE_MM ]] && TRY_TO_DISABLE_MM="true"

# Function to load external scripts
load_external_scripts() {
    for script_path in "${external_scripts[@]}"; do
        if [ ! -f "$script_path" ]; then
            echo -e "${red}Error: Required script not found: $script_path${normal}"
            exit 1
        fi
        if [ ! -r "$script_path" ]; then
            echo -e "${red}Error: Script not readable: $script_path${normal}"
            exit 1
        fi
        echo -e "${blue}Loading external script: $(basename "$script_path")${normal}"
        source "$script_path"
    done
}

# Validate input parameters
validate_parameters() {
    if [ -z "${COMP_NODE_NAME}" ]; then
        echo -e "${red}Error: Compute node name required as script parameter${normal}"
        echo "Usage: $0 <compute_node_name>"
        exit 1
    fi
}

# Check openstack cli
check_openstack_cli() {
    if [[ $CHECK_OPENSTACK = "true" ]]; then
        if ! bash $utils_dir/$check_openstack_cli_script; then
            exit 1
        fi
    fi
}

# Check and source openrc
check_and_source_openrc_file() {
    if bash $utils_dir/$check_openrc_script &> /dev/null; then
        openrc_file=$(bash $utils_dir/$check_openrc_script)
        source $openrc_file
    else
        bash $utils_dir/$check_openrc_script
        exit 1
    fi
}

# Check nova service list
check_nova_service_list() {
    echo -e "${violet}Check nova service list...${normal}"
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
check_connection_to_node() {
    local node_name=$1
    local node_ip=$2

    echo "Checking connection to $node_name ($node_ip)..."

    if ping -c 2 "$node_ip" &> /dev/null; then
        echo -e "${green}Connection to $node_name successful${normal}"
        return 0
    else
        echo -e "${red}No connection to $node_name at IP: $node_ip - ERROR!${normal}"
        echo -e "${yellow}The node may be powered off.${normal}"
        return 1
    fi
}

# Check container status on node
check_container_status() {
    local node_ip=$1
    local container_engine=$2

    echo "Checking container status on node..."

    local container_status
    container_status=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo $container_engine ps" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo -e "${red}Failed to check container status on node${normal}"
        return 1
    fi

    echo "$container_status"
}

# Start compute services
start_compute_services() {
    local node_ip=$1
    local container_engine=$2

    echo "Starting compute services..."

    # Check if nova_compute container is running
    local docker_nova_started
    docker_nova_started=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo $container_engine ps" | grep nova_compute)

    if [ -z "$docker_nova_started" ]; then
        echo "Starting kolla services and containers..."
        ssh -o StrictHostKeyChecking=no -t "$SSH_USER@$node_ip" \
            "sudo systemctl start kolla-consul-container.service kolla-nova_compute-container.service"
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "sudo $container_engine start consul nova_compute"
    else
        echo "Restarting nova compute containers..."
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "sudo $container_engine restart consul nova_compute"
    fi

    # Wait for services to start
    echo "Waiting $WAIT_TIME seconds for services to start..."
    sleep $WAIT_TIME
}

# Enable compute service in OpenStack
enable_compute_service() {
    local node_name=$1

    echo "Enabling compute service for $node_name in OpenStack..."

    if openstack compute service set --enable --up "${node_name}" nova-compute; then
        echo -e "${green}Compute service enabled successfully for $node_name${normal}"
        return 0
    else
        echo -e "${red}Failed to enable compute service for $node_name${normal}"
        return 1
    fi
}

# Try to disable maintenance mode
try_to_disable_maintenance_mode() {
    local hyper_name=$1

    if [ "$TRY_TO_DISABLE_MM" != "true" ]; then
        echo "Maintenance mode disable skipped (TRY_TO_DISABLE_MM=false)"
        return 0
    fi

    echo "Attempting to disable maintenance mode for $hyper_name..."

    local hyper_id
    hyper_id=$(openstack compute service list | grep -m 1 "$hyper_name" | awk '{print $2}')

    if [ -z "$hyper_id" ]; then
        echo -e "${yellow}Could not find hypervisor ID for $hyper_name${normal}"
        return 1
    fi

    local internal_FQDN=${OS_AUTH_URL/:5000}

    [ "$TS_DEBUG" = true ] && echo "
    [DEBUG]
        internal_FQDN: $internal_FQDN
        login: $OS_USERNAME,
        user_domain_name: $OS_USER_DOMAIN_NAME,
        project_name: $OS_PROJECT_NAME,
        project_domain_name: $OS_PROJECT_DOMAIN_NAME
        hyper_id: $hyper_id
    "

    # Get authentication token
    local TOKEN
    TOKEN=$(curl -s -H "Content-Type: application/json" -H 'accept: application/json' -X POST $internal_FQDN:13000/login \
        -d '{
              "login": "'"$OS_USERNAME"'",
              "password": "'"$OS_PASSWORD"'",
              "user_domain_name": "'"$OS_USER_DOMAIN_NAME"'",
              "project_name": "'"$OS_PROJECT_NAME"'",
              "project_domain_name": "'"$OS_PROJECT_DOMAIN_NAME"'"
            }' | python3 -c "import sys, json; print(json.load(sys.stdin)['X-Auth-Token'])" 2>/dev/null)

    if [ -z "$TOKEN" ]; then
        echo -e "${yellow}Failed to get authentication token${normal}"
        return 1
    fi

    # Disable maintenance mode
    echo "Sending maintenance mode disable request..."
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "X-Auth-Token: $TOKEN" \
        -X PUT "$internal_FQDN":12999/api/"$OS_REGION_NAME"/hypervisors/"$hyper_id"/maintenance_mode_off)

    if [ "$response" = "200" ] || [ "$response" = "202" ]; then
        echo -e "${green}Maintenance mode disabled successfully${normal}"
        return 0
    else
        echo -e "${yellow}Failed to disable maintenance mode (HTTP $response)${normal}"
        return 1
    fi
}

# Main execution function
main() {
    echo "$script_name script started..."

    # Validate parameters first
    validate_parameters

    # Load external scripts
    load_external_scripts

    # Get and validate SSH user
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi
    echo -e "${green}Using SSH user: $SSH_USER${normal}"

    # Check OpenStack environment
    check_openstack_cli
    check_and_source_openrc_file

    # Get compute node details
    echo "Getting details for compute node: $COMP_NODE_NAME"
    compute_node_pair=$(get_nodes_list -nn "$COMP_NODE_NAME")
    node_name="${compute_node_pair%%:*}"
    node_ip="${compute_node_pair#*:}"

    echo -e "${blue}Compute node details:${normal}"
    echo "  Name: $node_name"
    echo "  IP: $node_ip"

    # Check connection to compute node
    if ! check_connection_to_node "$node_name" "$node_ip"; then
        echo -e "${red}Failed to enable nova service on $node_name - cannot establish connection${normal}"
        exit 1
    fi

    # Start compute services
    start_compute_services "$node_ip" "$CONTAINER_ENGINE"

    # Enable service in OpenStack
    if ! enable_compute_service "$node_name"; then
        echo -e "${red}Failed to enable compute service in OpenStack${normal}"
        exit 1
    fi

    # Try to disable maintenance mode
    try_to_disable_maintenance_mode "$COMP_NODE_NAME"

    # Final check
    if [ "$CHECK_AFTER" = "true" ]; then
        echo -e "${green}Final service status check:${normal}"
        check_nova_service_list
    fi

    echo -e "${green}Script completed successfully!${normal}"
    echo -e "${green}Compute service on $node_name has been started and enabled${normal}"
}

# Run main function
main