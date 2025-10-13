#!/bin/bash

# The script copy block_traffic script to node and start it by ssh

# BLOCKED_IPS=("<IP_ctrl_1>" "<IP_ctrl_2>" "<IP_3>" "...")
# example
# BLOCKED_IPS=("10.224.133.138" "10.224.133.139" "10.224.133.133" "10.224.133.134" "10.224.133.135")

# Script paths
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_ssh_user_script="get_ssh_user.sh"
default_ssh_user="root"

# Default values
[[ -z $NODE_TO_BLOCK_TRAFFIC ]] && NODE_TO_BLOCK_TRAFFIC=""
[[ -z $SSH_USER ]] && SSH_USER=""

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Copy block_traffic script to node and start it by ssh

    Options:
      -n, -node <node_name>          Node name to block traffic on
      -u, -user <username>           SSH username
      --help                         Show this help message
    "
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

# Parse command line arguments
parse_arguments() {
    while [ -n "$1" ]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            -n|-node)
                NODE_TO_BLOCK_TRAFFIC="$2"
                echo "Found the -node <node_name> option, with parameter value $NODE_TO_BLOCK_TRAFFIC"
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

# Main execution function
main() {
    parse_arguments "$@"
    load_external_scripts

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to determine valid SSH user!"
        exit 1
    fi

    echo "Using SSH user: $SSH_USER"

    [[ -z $NODE_TO_BLOCK_TRAFFIC ]] && {
        echo "node name needed to block traffic (env NODE_TO_BLOCK_TRAFFIC) or start this script with key -n <node_name>";
        exit 1;
    }

    scp ./block_traffic.sh "$SSH_USER@$NODE_TO_BLOCK_TRAFFIC":~/
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$NODE_TO_BLOCK_TRAFFIC" 'chmod 777 ~/block_traffic.sh'
    ssh -t -o StrictHostKeyChecking=no "$SSH_USER@$NODE_TO_BLOCK_TRAFFIC" 'echo '"${BLOCKED_IPS[*]}"' > ~/blocked_ips_list'
    ssh -t -o StrictHostKeyChecking=no "$SSH_USER@$NODE_TO_BLOCK_TRAFFIC" 'bash ~/block_traffic.sh'
}

# Run main function
main "$@"