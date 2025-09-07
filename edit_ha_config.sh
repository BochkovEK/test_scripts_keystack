#!/bin/bash

# Script for managing HA configuration files across consul nodes
# Supports pulling, pushing, and checking configuration files

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
cyan=$(tput setaf 14)
#violet=$(tput setaf 5)

# Service and path configuration
service_name="consul"
nodes_type="ctrl"
test_node_conf_dir="kolla/$service_name"
conf_dir="/etc/kolla/$service_name"
conf_name="ha-config.ini"

# Script paths
script_dir=$(dirname "$0")
script_name=$(basename "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
default_ssh_user="root"
#check_openrc_script="check_openrc.sh"

# Default values
CHECK_SUFFIX="${CHECK_SUFFIX:-false}"
DEBUG="${DEBUG:-false}"
ONLY_CONF_CHECK="${ONLY_CONF_CHECK:-false}"
PUSH="${PUSH:-false}"
PULL="${PULL:-false}"
CONF_NAME="${CONF_NAME:-$conf_name}"
OS_REGION_NAME="${OS_REGION_NAME:-}"
GET_CONFIG_PATH="${GET_CONFIG_PATH:-false}"
#LEGACY_CONF="${LEGACY_CONF:-false}"

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Manage HA configuration files across consul nodes.

    Options:
      suffix                            Return BMC suffix
      config_path                       Return configuration file path
      -v, -debug                        Enable debug output
      -pull                             Pull configuration from controller node to local directory
      -push                             Push configuration from local directory to all controller nodes
      -check                            Only check configuration without making changes
      -u, -ssh_user <user>              Set SSH user for remote access
      -ce, -container_engine <engine>   Container engine (docker/podman)
      -suffix                           Get BMC suffix
    "
}
#      -l, -legacy          Work with legacy consul region config
#      Legacy Configuration Note:
#      For legacy consul versions:
#        1) Use -l or -legacy flag
#        2) Define OS_REGION_NAME environment variable or use openrc file
#        Example: bash $script_name -check -l

# Function to define parameters from positional arguments
define_parameters() {
    [ "$count" = 1 ] && [ "$1" = "suffix" ] && {
        CHECK_SUFFIX=true
        echo "Check suffix parameter found"
    }
    [ "$count" = 1 ] && [ "$1" = "config_path" ] && {
        GET_CONFIG_PATH=true
        echo "Get config path parameter found"
    }
}

# Function to get nodes list using external script
get_nodes_list() {
    [ "$DEBUG" = true ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*"

    local nodes_result=""

    [ "$DEBUG" = true ] && echo -e "
    [DEBUG]:
      nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" \"$*\")"

    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")

    [ "$DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result: $nodes_result"

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

# Parse command line arguments
parse_arguments() {
    local count=1
    while [ -n "$1" ]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            -v|-debug)
                DEBUG="true"
                echo "Debug mode enabled"
                shift
                ;;
            -pull)
                PULL="true"
                echo "Pull mode enabled"
                shift
                ;;
            -push)
                PUSH="true"
                echo "Push mode enabled"
                shift
                ;;
            -check)
                ONLY_CONF_CHECK="true"
                echo "Check mode enabled"
                shift
                ;;
            -ce|-container_engine)
                CONTAINER_ENGINE="$2"
                echo "Using container engine: $CONTAINER_ENGINE"
                shift 2
                ;;
            -suffix)
                CHECK_SUFFIX="true"
                echo "Suffix check enabled"
                shift
                ;;
            -u|-ssh_user)
                SSH_USER="$2"
                echo "Using SSH user: $SSH_USER"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Parameter #$count: $1"
                define_parameters "$1"
                count=$((count + 1))
                shift
                ;;
        esac
    done
}

#-l|-legacy)
#                LEGACY_CONF="true"
#                echo "Legacy configuration mode enabled"
#                shift
#                ;;

## Function to check and source openrc file
#check_and_source_openrc_file() {
#    echo -e "${violet}Checking openrc file...${normal}"
#    if bash "$utils_dir/$check_openrc_script" &> /dev/null; then
#        openrc_file=$(bash "$utils_dir/$check_openrc_script")
#        echo -e "${green}$openrc_file file exists - success${normal}"
#        source "$openrc_file"
#    else
#        bash "$utils_dir/$check_openrc_script"
#        echo -e "${red}OpenRC file not found - ERROR${normal}"
#        exit 1
#    fi
#}

# Function to display configuration files
cat_conf() {
    echo "Displaying all $service_name configurations..."
    local nodes
    nodes=$(get_nodes_list -nt "$nodes_type")

    for node in $nodes; do
        local node_name="${node%%:*}"
        local node_ip="${node#*:}"
        echo -e "${cyan}Configuration on $node_name:${normal}"
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "sudo cat $conf_dir/$CONF_NAME 2>/dev/null || echo 'Configuration file not found'"
        echo "----------------------------------------"
    done
}

# Function to pull configuration from controller node
pull_conf() {
    echo "Pulling $CONF_NAME from controller node..."

    local nodes
    local first_node

    # Create local directory if it doesn't exist
    [ ! -d "$script_dir/$test_node_conf_dir" ] && mkdir -p "$script_dir/$test_node_conf_dir"

    # Get nodes list
    nodes=$(get_nodes_list -nt "$nodes_type")
    first_node=$(echo "$nodes" | head -n1)

    if [ -z "$first_node" ]; then
        echo -e "${red}No controller nodes found${normal}"
        exit 1
    fi

    local node_name="${first_node%%:*}"
    local node_ip="${first_node#*:}"

    echo "Copying $service_name configuration from ${node_name}:$conf_dir/$CONF_NAME"

    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        first_node: $first_node
        node_name:  $node_name
        node_ip:    $node_ip
        Command:    ssh -o StrictHostKeyChecking=no \"$SSH_USER@$node_ip\" \
        \"sudo cat $conf_dir/$CONF_NAME\" > \"$script_dir/$test_node_conf_dir/${CONF_NAME}\"
    "
    # Copy configuration file
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo cat $conf_dir/$CONF_NAME" > "$script_dir/$test_node_conf_dir/${CONF_NAME}"

    # Check config on local host
    if [ ! -f "$script_dir/$test_node_conf_dir/${CONF_NAME}" ]; then
        echo -e "${red}Configuration file is missing in ${normal}"
        exit 1
    fi

    # Create backup if it doesn't exist
    [ ! -f "$script_dir/$test_node_conf_dir/${CONF_NAME}_backup" ] && \
        cp "$script_dir/$test_node_conf_dir/${CONF_NAME}" "$script_dir/$test_node_conf_dir/${CONF_NAME}_backup"

    echo -e "
To edit the configuration:
  vi $script_dir/$test_node_conf_dir/$CONF_NAME

To apply the configuration:
  bash $script_dir/$script_name -push
"
}

# Function to push configuration to controller nodes
push_conf() {
    echo "Pushing $CONF_NAME to controller nodes..."

    if [ ! -f "$script_dir/$test_node_conf_dir/$CONF_NAME" ]; then
        echo -e "${red}Configuration file not found: $script_dir/$test_node_conf_dir/$CONF_NAME${normal}"
        exit 1
    fi

    # Get nodes list
    local nodes
    nodes=$(get_nodes_list -nt "$nodes_type")

    for node in $nodes; do
        local node_name="${node%%:*}"
        local node_ip="${node#*:}"

        echo "Pushing configuration to $node_name"

        # Get node IP for bind address replacement
        local node_actual_ip
        node_actual_ip=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "hostname -I | awk '{print \$1}'" 2>/dev/null)

        if [ -n "$node_actual_ip" ]; then
            # Create temporary file with replaced IP addresses
            local temp_file
            temp_file=$(mktemp)
            sed -E "
                s/\"bind_address\"[[:space:]]*:[[:space:]]*\"[0-9.]+[0-9]+\"/\"bind_address\": \"$node_actual_ip\"/g
                s/consul_host[[:space:]]*=[[:space:]]*[0-9.]+[0-9]+/consul_host = $node_actual_ip/g
            " "$script_dir/$test_node_conf_dir/$CONF_NAME" > "$temp_file"

            # Copy file to remote node
            scp -o StrictHostKeyChecking=no "$temp_file" "$SSH_USER@$node_ip:/tmp/$CONF_NAME"
            ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
                "sudo mv /tmp/$CONF_NAME $conf_dir/$CONF_NAME && sudo chown root:root $conf_dir/$CONF_NAME"

            # Clean up temporary file
            rm -f "$temp_file"

            echo -e "${green}Configuration pushed to $node_name${normal}"
        else
            echo -e "${red}Failed to get IP address for $node_name${normal}"
        fi
    done
}

# Function to check BMC suffix
check_bmc_suffix() {
    pull_conf

    if [ ! -f "$script_dir/$test_node_conf_dir/$CONF_NAME" ]; then
        echo -e "${red}Configuration file not found${normal}"
        exit 1
    fi

    local suffix_string_raw
    suffix_string_raw=$(grep 'suffix' "$script_dir/$test_node_conf_dir/$CONF_NAME")

    if [ "$LEGACY_CONF" = true ]; then
        local suffix_string_raw_2="${suffix_string_raw//\"/}"
        echo "${suffix_string_raw_2%%,*}" | awk '{print $2}'
    else
        echo "$suffix_string_raw" | awk '{print $3}'
    fi
}

# Function to get configuration path
get_config_path() {
    echo "$conf_dir/$CONF_NAME"
}

# Function to determine SSH user
determine_ssh_user() {
    if [ -z "$SSH_USER" ]; then
        SSH_USER=$(whoami 2>/dev/null) || {
            echo -e "${yellow}Warning: Failed to determine user via whoami${normal}" >&2
            SSH_USER="$default_ssh_user"
        }
    fi

    if [ -z "$SSH_USER" ]; then
        echo -e "${red}Error: Failed to determine SSH user!${normal}" >&2
        exit 1
    fi
}

# Main execution function
main() {
    parse_arguments "$@"
    determine_ssh_user

#    # Handle legacy configuration
#    if [ "$LEGACY_CONF" = true ]; then
#        if [ -z "$OS_REGION_NAME" ]; then
#            check_and_source_openrc_file
#        fi
#        if [ -z "$OS_REGION_NAME" ]; then
#            echo -e "${red}Region name not found${normal}"
#            exit 1
#        fi
#        CONF_NAME="region-config_${OS_REGION_NAME}.json"
#    fi

    # Execute requested actions
    if [ "$CHECK_SUFFIX" = true ]; then
        check_bmc_suffix
        exit 0
    fi

    if [ "$GET_CONFIG_PATH" = true ]; then
        get_config_path
        exit 0
    fi

    if [ "$ONLY_CONF_CHECK" = true ]; then
        cat_conf
        exit 0
    fi

    if [ "$PULL" = true ]; then
        pull_conf
        exit 0
    fi

    if [ "$PUSH" = true ]; then
        push_conf
        # Restart consul containers after configuration change
        echo "Restarting consul containers..."
        bash "$script_dir/command_on_nodes.sh" -u "$SSH_USER" -nt ctrl -c "sudo $CONTAINER_ENGINE restart consul"
    fi

    # Show configuration after changes
    cat_conf
}

# Run main function
main "$@"