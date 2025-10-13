#!/bin/bash

# The script copy block_traffic script to node and start it by ssh

# BLOCKED_IPS="<IP_ctrl_1> <IP_ctrl_2> ... <IP_N>"
# example
# BLOCKED_IPS="10.224.133.138 10.224.133.139 10.224.133.133 10.224.133.134 10.224.133.135"

# Color definitions
normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
red=$(tput setaf 1)

# Script paths
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
get_ssh_user_script="get_ssh_user.sh"
default_ssh_user="root"
target_block_ips_list_dir="/tmp"
block_traffic_script="block_traffic.sh"
blocked_ips_list_file_name="blocked_ips_list"

# Default values
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $SSH_USER ]] && SSH_USER="$default_ssh_user"
[[ -z $BLOCKED_IPS ]] && BLOCKED_IPS=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Copy block_traffic script to node and start it by ssh

    Options:
      -n, -nodes <nodes_name_list>   Node name to block traffic on \"<node_name_1> <node_name_2> ... <node_name_N>\"
      -bl -black_list <black_list>   List of blocked IPs: \"<blocked_traffic_from_node_IP_1> <IP_2> ... <IP_N>\"
      -u, -user <username>           SSH username
      --help                         Show this help message
    "
}

# Parse command line arguments
parse_arguments() {
    while [ -n "$1" ]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            -n|-nodes)
                NODES_NAME="$2"
                echo "Found the -node <node_name> option, with parameter value $NODES_NAME"
                shift
                ;;
            -bl|-black_list)
                BLOCKED_IPS="$2"
                echo "Found the -black_list option, with parameter value $BLOCKED_IPS"
                shift
                ;;
            -u|-user)
                SSH_USER="$2"
                echo "Found the -user option, with parameter value $SSH_USER"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$1 is not an option"
                ;;
        esac
        shift
    done
}

# Function to load external scripts
load_external_scripts() {
    local script_path="$utils_dir/$get_ssh_user_script"
    if [ ! -f "$script_path" ]; then
        echo -e "Error: Required script not found: $script_path"
        exit 1
    fi
    source "$script_path"
}

# Function to confirm action
confirm_blocking() {
    local node_name="$1"
    local node_ip="$2"
echo -e "${yellow}============== BLOCKING TRAFFIC ===============
Nodes to block:
⚠
$(echo "$BLOCKED_NODES_PAIR" | tr ' ' '\n')
Target node:
💻
$node_name
================================================${normal}"
    read -p "Press Enter to continue or Ctrl+C to cancel..."
}

# Function to get blocked IPs list
get_blocked_ips () {
    BLOCKED_NODES_PAIR=$(get_nodes_list "-nt" "all")
    for bn in $BLOCKED_NODES_PAIR; do
        blocked_node_name="${bn%%:*}"
        blocked_node_ip="${bn#*:}"
        if [ -z "$BLOCKED_IPS" ]; then
            BLOCKED_IPS="$blocked_node_ip"
        else
            BLOCKED_IPS="$BLOCKED_IPS $blocked_node_ip"
        fi
    done
}

# Function block traffic on node
block_traffic_on_node () {
    local node_name="$1"
    local node_ip="$2"

    confirm_blocking "$node_name" "$node_ip"
    echo "${yellow}Blocking traffic on ${node_name}...${normal}"

    scp "${script_dir}/${block_traffic_script}" "$SSH_USER@$node_ip":~/
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo chmod 777 ~/$block_traffic_script"
    ssh -t -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo echo ${BLOCKED_IPS} > ${target_block_ips_list_dir}/${blocked_ips_list_file_name}"
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "sudo bash ~/$block_traffic_script > ${target_block_ips_list_dir}/block_traffic.log 2>&1 &"
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

# Function block traffic
block_traffic () {
    local nodes_pair
    nodes_pair=$(get_nodes_list "-nn" "$NODES_NAME")
    for node_pair in $nodes_pair; do
        node_name="${node_pair%%:*}"
        node_ip="${node_pair#*:}"
        block_traffic_on_node "$node_name" "$node_ip"
    done
}

# Main execution function
main() {
    parse_arguments "$@"
    loca nodes_pair
    load_external_scripts

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to determine valid SSH user!"
        exit 1
    fi

    echo "Using SSH user: $SSH_USER"

    if [ -z "$NODES_NAME" ]; then
        echo -e "${yellow}Node name needed to block traffic (env NODES_NAME) or start this script with key -n <node_name>${normal}";
        exit 1;
    fi

    [[ -z "$BLOCKED_IPS" ]] && get_blocked_ips
    if [ -z "$BLOCKED_IPS" ]; then
        echo -e "${yellow}IP addresses needed to block traffic (env BLOCKED_IPS) or start this script with key -bl <ip_list>${normal}";
        exit 1;
    fi

    block_traffic
}

# Run main function
main "$@"
