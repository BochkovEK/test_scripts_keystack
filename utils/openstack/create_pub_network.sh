#!/bin/bash

# The script create pub_net from LCM or jump host only
# To get pub_net settings:
# export GET_SETTINGS=true
# bash ~/test_scripts_keystack/utils/openstack/create_pub_network.sh

# Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)

# Script_dir, current folder
default_ssh_user="root"
script_name=$(basename "$0")
script_file_path=$(realpath $0)
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir=$parent_dir
get_nodes_list_script="get_nodes_list.sh"
check_openrc_script="check_openrc.sh"
yes_no_answer_script="yes_no_answer.sh"
get_ssh_user_script="get_ssh_user.sh"

# External scripts array
external_scripts=(
    "$utils_dir/$yes_no_answer_script"
    "$utils_dir/$get_ssh_user_script"
)

# Default values
[[ -z $DONT_ASK ]] && DONT_ASK="false"
[[ -z $CHECK_OPENSTACK ]] && CHECK_OPENSTACK="true"
[[ -z $PROJECT ]] && PROJECT="admin"
[[ -z $API_VERSION ]] && API_VERSION="2.74"
[[ -z $NETWORK ]] && NETWORK="pub_net"
[[ -z $TS_DEBUG ]] && TS_DEBUG="true"
[[ -z $GET_SETTINGS ]] && GET_SETTINGS="false"

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

# Universal confirmation function with DONT_ASK support
confirm_action_universal() {
    local message="$1"
    local default_answer="${2:-"Yes"}"

    if [[ $DONT_ASK = "true" ]]; then
        echo -e "${green}Auto-confirmed (DONT_ASK): $message${normal}"
        return 0
    fi

    # Use external confirmation function
    confirm_action_external "$message" "$default_answer"
}

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -u, -user <username>          SSH username
      -debug                        Enable debug output
      --help                        Show this help message
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
            -u|-user)
                SSH_USER="$2"
                echo "Found -user with value: $SSH_USER"
                shift
                ;;
            -debug)
                TS_DEBUG="true"
                echo "Found -debug option"
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Unknown parameter: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

error_output() {
    if [ -n "${warning_message}" ]; then
        printf "%s\n" "${yellow}$warning_message${normal}"
        warning_message=""
    fi
    printf "%s\n" "${red}$error_message - error${normal}"
    exit 1
}

check_and_source_openrc_file() {
    if bash $utils_dir/$check_openrc_script &> /dev/null; then
        openrc_file=$(bash $utils_dir/$check_openrc_script)
        source $openrc_file
    else
        bash $utils_dir/$check_openrc_script
        exit 1
    fi
}

# Check OpenStack CLI
check_openstack_cli () {
    if ! command -v openstack &> /dev/null; then
        echo -e "${red}OpenStack CLI not found${normal}"
        exit 1
    fi
}

# Check network settings
get_settings() {
    local node_pair=$(bash "$utils_dir/$get_nodes_list_script" -nt lcm | awk '{print $1}')
    local node_ip="${node_pair#*:}"

    if [ -z "$node_ip" ]; then
        warning_message="Could not determine LCM node IP address"
        error_message="Network settings cannot be retrieved"
        error_output
    fi

    echo "Retrieving network settings from LCM node: $node_ip"

    # Get CIDR from LCM node
    CIDR=$(ssh $SSH_USER@$node_ip "sudo ip r | grep 'dev external proto kernel scope'" | awk '{print $1}')

    if [ -z "$CIDR" ]; then
        warning_message="Could not determine CIDR from LCM node"
        error_message="Network settings retrieval failed"
        error_output
    fi

    # Calculate gateway and IP ranges
    local last_digit=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\.[0-9]+\.[0-9]+\.)|(\/[0-9]+)//g')
    local left_side=$(echo $CIDR | sed --regexp-extended 's/([0-9]+\/[0-9]+)//g')
    GATEWAY=$left_side$(expr $last_digit + 1)

    if [ -n "$CIDR" ] && [ -n "$GATEWAY" ]; then
        local mask_pub_net=$(echo "${CIDR##*/}")
        if [ "$mask_pub_net" = "27" ]; then
            case "$last_digit" in
                0)
                    start_pub_net_ip="${left_side}10"
                    end_pub_net_ip="${left_side}30"
                    ;;
                32)
                    start_pub_net_ip="${left_side}40"
                    end_pub_net_ip="${left_side}62"
                    ;;
                64)
                    start_pub_net_ip="${left_side}70"
                    end_pub_net_ip="${left_side}94"
                    ;;
                96)
                    start_pub_net_ip="${left_side}100"
                    end_pub_net_ip="${left_side}126"
                    ;;
                128)
                    start_pub_net_ip="${left_side}140"
                    end_pub_net_ip="${left_side}158"
                    ;;
                160)
                    start_pub_net_ip="${left_side}170"
                    end_pub_net_ip="${left_side}190"
                    ;;
                192)
                    start_pub_net_ip="${left_side}200"
                    end_pub_net_ip="${left_side}222"
                    ;;
                224)
                    start_pub_net_ip="${left_side}230"
                    end_pub_net_ip="${left_side}254"
                    ;;
                *)
                    warning_message="Unsupported CIDR range: $CIDR"
                    error_message="Network $NETWORK cannot be created"
                    error_output
                    ;;
            esac
        else
            warning_message="The script can only create a 'pub_net' with '27' mask (current: $mask_pub_net)"
            error_message="Network $NETWORK cannot be created"
            error_output
        fi
    else
        warning_message="Script can't define CIDR or GATEWAY on this node. Try use the script on LCM or jump node"
        error_message="Network $NETWORK cannot be created"
        error_output
    fi

    echo -e "${green}Network settings retrieved successfully${normal}"
}

# Create network in OpenStack
create_network_in_openstack() {
    echo "Creating network: $NETWORK"

    if openstack network create \
        --external \
        --share \
        --provider-network-type flat \
        --provider-physical-network physnet1 \
        $NETWORK; then
        echo -e "${green}Network $NETWORK created successfully${normal}"
        return 0
    else
        return 1
    fi
}

# Create subnet in OpenStack
create_subnet_in_openstack() {
    echo "Creating subnet for network: $NETWORK"

    if openstack subnet create \
        --subnet-range $CIDR \
        --network $NETWORK \
        --dhcp \
        --gateway $GATEWAY \
        --allocation-pool start=$start_pub_net_ip,end=$end_pub_net_ip \
        $NETWORK; then
        echo -e "${green}Subnet for $NETWORK created successfully${normal}"
        return 0
    else
        return 1
    fi
}

# Verify network creation
verify_network_creation() {
    local max_attempts=10
    local attempt=1

    echo "Verifying network creation..."

    while [ $attempt -le $max_attempts ]; do
        local network_exists=$(openstack network list | grep "$NETWORK" | awk '{print $2}')

        if [ -n "$network_exists" ]; then
            echo -e "${green}Network $NETWORK successfully created and verified${normal}"
            return 0
        fi

        echo "Attempt $attempt/$max_attempts: Network not ready yet, waiting..."
        sleep 3
        ((attempt++))
    done

    error_message="Network $NETWORK creation verification timeout"
    return 1
}

# Create pub network
create_pub_network() {
    echo "Checking if network \"$NETWORK\" exists in OpenStack..."

    local network_exists=$(openstack network list | grep "$NETWORK" | awk '{print $2}')

    if [ -n "$network_exists" ]; then
        echo -e "${green}Network \"$NETWORK\" already exists in project \"$PROJECT\"${normal}"
        return 0
    fi

    echo -e "${yellow}Network \"$NETWORK\" not found in project \"$PROJECT\"${normal}"

    if [ "$NETWORK" != "pub_net" ]; then
        warning_message="The script can only create a 'pub_net' network"
        error_message="Network $NETWORK cannot be created"
        error_output
    fi

    # Confirm network creation
    if ! confirm_action_universal "Do you want to create network: $NETWORK with CIDR: $CIDR?" "Yes"; then
        echo -e "${yellow}Network $NETWORK creation cancelled${normal}"
        return 1
    fi

    # Create network and subnet
    if create_network_in_openstack && create_subnet_in_openstack; then
        if verify_network_creation; then
            echo -e "${green}Network $NETWORK and subnet created successfully!${normal}"
            return 0
        else
            error_message="Network creation verification failed"
            error_output
        fi
    else
        error_message="Failed to create network or subnet"
        error_output
    fi
}

# Display settings (for GET_SETTINGS mode)
display_settings() {
    echo -e "${green}Network Settings:${normal}"
    echo "    CIDR:               $CIDR"
    echo "    GATEWAY:            $GATEWAY"
    echo "    Start IP pool:      $start_pub_net_ip"
    echo "    End IP pool:        $end_pub_net_ip"
    echo "    Network:            $NETWORK"
    echo "    Project:            $PROJECT"
}

# Main execution function
main() {
    echo "$script_name script started..."

    # Load external scripts first
    load_external_scripts

    # Parse command line arguments
    parse_arguments "$@"

    # Get and validate SSH user
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi
    echo -e "${green}Using SSH user: $SSH_USER${normal}"

    # Debug information
    if [ "$TS_DEBUG" = true ]; then
        echo -e "
  [TS_DEBUG]
  OS_PROJECT_DOMAIN_NAME:   $OS_PROJECT_DOMAIN_NAME
  OS_USER_DOMAIN_NAME:      $OS_USER_DOMAIN_NAME
  OS_PROJECT_NAME:          $OS_PROJECT_NAME
  OS_TENANT_NAME:           $OS_TENANT_NAME
  OS_USERNAME:              $OS_USERNAME
  OS_PASSWORD:              $OS_PASSWORD
  OS_AUTH_URL:              $OS_AUTH_URL
  OS_INTERFACE:             $OS_INTERFACE
  OS_ENDPOINT_TYPE:         $OS_ENDPOINT_TYPE
  OS_IDENTITY_API_VERSION:  $OS_IDENTITY_API_VERSION
  OS_REGION_NAME:           $OS_REGION_NAME
  OS_AUTH_PLUGIN:           $OS_AUTH_PLUGIN
  OS_DRS_ENDPOINT_OVERRIDE: $OS_DRS_ENDPOINT_OVERRIDE
  ---
  PROJECT:                  $PROJECT
  NETWORK:                  $NETWORK
  GET_SETTINGS:             $GET_SETTINGS
  SSH_USER:                 $SSH_USER
"
    fi

    # Get network settings
    get_settings

    # If only settings are requested, display and exit
    if [ "$GET_SETTINGS" = "true" ]; then
        display_settings
        exit 0
    fi

    # Create the network
    check_openstack_cli
    check_and_source_openrc_file
    create_pub_network

    echo -e "${green}Script completed successfully!${normal}"
}

# Run main function
main "$@"