#!/bin/bash

# Script for managing HA configuration files across consul nodes
# Supports pulling, pushing, and checking configuration files

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
cyan=$(tput setaf 6)

# Script paths
script_dir=$(dirname "$0")
script_name=$(basename "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
get_ssh_user_script="get_ssh_user.sh"
default_ssh_user="root"

# Service and path configuration
service_name="consul"
nodes_type="ctrl"
test_node_conf_dir="kolla/$service_name"
conf_dir="/etc/kolla/$service_name"
conf_name="ha-config.ini"

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
)

# Default values
CHECK_SUFFIX="${CHECK_SUFFIX:-false}"
TS_DEBUG="${TS_DEBUG:-false}"
ONLY_CONF_CHECK="${ONLY_CONF_CHECK:-false}"
PUSH="${PUSH:-false}"
PULL="${PULL:-false}"
CONF_NAME="${CONF_NAME:-$conf_name}"
OS_REGION_NAME="${OS_REGION_NAME:-}"
GET_CONFIG_PATH="${GET_CONFIG_PATH:-false}"
SSL_CHECK="${SSL_CHECK:-false}"

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
      -sc, -ssl_check                   Check for SSL client key in config
    "
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
                TS_DEBUG="true"
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
            -sc|-ssl_check)
                SSL_CHECK="true"
                echo "SSL check enabled"
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

# Function to check for SSL client key in config
#check_ssl_config() {
#    local config_file="$script_dir/$test_node_conf_dir/$CONF_NAME"
#
#    if [ ! -f "$config_file" ]; then
#        echo -e "${red}Configuration file not found: $config_file${normal}"
#        return 1
#    fi
#
#    if grep -q "client_key = .*\.pem" "$config_file"; then
#        echo "mtls"
#        return 0
#    else
#        echo -e "${yellow}No SSL client key found in configuration${normal}"
#        return 1
#    fi
#}

# Function to get nodes list using external script
get_nodes_list() {
#    [ "$TS_DEBUG" = true ] && echo -e "
#    [DEBUG]:
#        Count parameters: $#
#        Parameters: $*
#    "

    local nodes_result=""

    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")

#    [ "$TS_DEBUG" = true ] && echo -e "
#    [DEBUG] nodes_result: $nodes_result"

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

# Function to check for SSL client key in config and extract SSL parameters
check_ssl_config() {
    local config_file
    local first_ctrl_node

    # Take only the first node for config reading
    first_ctrl_node=$(echo "$NODES" | awk '{print $1}')
    echo "first_ctrl_node: $first_ctrl_node"
    if [ -z "$first_ctrl_node" ]; then
        echo -e "${red}No nodes provided${normal}" >&2
        return 1
    fi

    if ! config_file=$(cat_conf "$first_ctrl_node"); then
        echo -e "${red}Configuration file not found: $config_file${normal}"
        return 1
    fi

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        config_file:
        $config_file
    "

    # Check if client key exists in config
    if ! echo "$config_file" | grep -q "client_key = .*\.pem"; then
        echo -e "${yellow}No SSL client key found in configuration${normal}"
        return 1
    fi

    # Extract SSL parameters with better parsing
    local https_ssl_verify client_key client_cert

    # Extract values with proper handling of quotes and spaces
    https_ssl_verify=$(echo "$config_file" | grep -qE "^https_ssl_verify\s*=" | head -1 | awk -F= '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
    client_key=$(echo "$config_file" | grep -qE "^client_key\s*=" | head -1 | awk -F= '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
    client_cert=$(echo "$config_file" | grep -qE "^client_cert\s*=" | head -1 | awk -F= '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')

    # Set default values if not found or empty
    https_ssl_verify="${https_ssl_verify:-/etc/pki/tls/certs/ca-bundle.crt}"
    client_key="${client_key:-/etc/consul/certs/consul-key.pem}"
    client_cert="${client_cert:-/etc/consul/certs/consul-cert.pem}"

    # Return formatted string
    echo "mtls; https_ssl_verify = $https_ssl_verify; client_key = $client_key; client_cert = $client_cert"
    return 0
}

# Function to display configuration files
#cat_conf() {
#    echo "Displaying all $service_name configurations..."
#    local nodes
#    nodes=$(get_nodes_list -nt "$nodes_type")
#
#    for node in $nodes; do
#        local node_name="${node%%:*}"
#        local node_ip="${node#*:}"
#        echo -e "${cyan}Configuration on $node_name:${normal}"
#        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
#            "sudo cat $conf_dir/$CONF_NAME 2>/dev/null || echo 'Configuration file not found'"
#        echo "----------------------------------------"
#    done
#}

# Function to display configuration files - returns config content
cat_conf() {
    local nodes_list="$1"

#    # If no nodes provided, get all nodes
#    if [ -z "$nodes_list" ]; then
#        nodes_list=$(get_node_names)
#    fi



#    # Get node IP for the first node
#    local nodes
#    nodes=$(get_nodes_list -nt "$nodes_type")
#    local node_ip=""
#
#    for node in $nodes; do
#        local node_name="${node%%:*}"
#        local current_ip="${node#*:}"
#        if [ "$node_name" = "$first_node" ]; then
#            node_ip="$current_ip"
#            break
#        fi
#    done

#    if [ -z "$node_ip" ]; then
#        echo -e "${red}Could not find IP for node: $first_node${normal}" >&2
#        return 1
#    fi

#    config_content=""
    for node in $nodes_list; do
        local node_name="${node%%:*}"
        local node_ip="${node#*:}"

        local node_config
        node_config=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "sudo cat $conf_dir/$CONF_NAME 2>/dev/null")

        echo -e "${cyan}Config from $node_name${normal}"
        echo -e "$node_config"


#        if [ -n "$node_config" ]; then
#            if [ -n "$config_content" ]; then
#                config_content="${config_content}\n---\n"
#            fi
#            config_content="${config_content}Config from $node_name\n${node_config}"
#        fi
    done
    return 0
}

# Function to pull configuration from controller node
pull_conf() {
    echo "Pulling $CONF_NAME from controller node..."

#    local nodes
    local first_node

    [ ! -d "$script_dir/$test_node_conf_dir" ] && mkdir -p "$script_dir/$test_node_conf_dir"

#    nodes=$(get_nodes_list -nt "$nodes_type")

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]: nodes: $nodes"

    first_node=$(echo "$NODES" | awk '{print $1}')

#    if [ -z "$first_node" ]; then
#        echo -e "${red}No controller nodes found${normal}"
#        exit 1
#    fi

    local node_name="${first_node%%:*}"
    local node_ip="${first_node#*:}"

    echo "Copying $service_name configuration from $node_name:$conf_dir/$CONF_NAME"

    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo cat $conf_dir/$CONF_NAME" > "$script_dir/$test_node_conf_dir/${CONF_NAME}"

    if [ ! -f "$script_dir/$test_node_conf_dir/${CONF_NAME}" ]; then
        echo -e "${red}Configuration file is missing${normal}"
        exit 1
    fi

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

    local nodes
    nodes=$(get_nodes_list -nt "$nodes_type")

    for node in $nodes; do
        local node_name="${node%%:*}"
        local node_ip="${node#*:}"

        echo "Pushing configuration to $node_name"

        local node_actual_ip
        node_actual_ip=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "hostname -I | awk '{print \$1}'" 2>/dev/null)

        if [ -n "$node_actual_ip" ]; then
            local temp_file
            temp_file=$(mktemp)
            sed -E "
                s/\"bind_address\"[[:space:]]*:[[:space:]]*\"[0-9.]+[0-9]+\"/\"bind_address\": \"$node_actual_ip\"/g
                s/consul_host[[:space:]]*=[[:space:]]*[0-9.]+[0-9]+/consul_host = $node_actual_ip/g
            " "$script_dir/$test_node_conf_dir/$CONF_NAME" > "$temp_file"

            scp -o StrictHostKeyChecking=no "$temp_file" "$SSH_USER@$node_ip:/tmp/$CONF_NAME"
            ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
                "sudo mv /tmp/$CONF_NAME $conf_dir/$CONF_NAME && sudo chown root:root $conf_dir/$CONF_NAME"

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

# Function to load external scripts
load_external_scripts() {
    for script_path in "${external_scripts[@]}"; do
        if [ ! -f "$script_path" ]; then
            echo -e "${red}Error: Required script not found: $script_path${normal}"
            exit 1
        fi
        source "$script_path"
    done
}

# Main execution function
main() {
    parse_arguments "$@"

    # Load external scripts first
    load_external_scripts

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi

    echo -e "${green}Using SSH user: $SSH_USER${normal}"

    # Get nodes list
    if ! NODES=$(get_nodes_list -nt $nodes_type); then
        exit 1
    fi

    if [ "$TS_DEBUG" = true ]; then
    echo -e "
    [DEBUG] NODES: $NODES
    "
    fi

    if [ "$SSL_CHECK" = true ]; then
        check_ssl_config
        exit 0
    fi

    if [ "$CHECK_SUFFIX" = true ]; then
        check_bmc_suffix
        exit 0
    fi

    if [ "$GET_CONFIG_PATH" = true ]; then
        get_config_path
        exit 0
    fi

    if [ "$ONLY_CONF_CHECK" = true ]; then
        cat_conf "$NODES"
        exit 0
    fi

    if [ "$PULL" = true ]; then
        pull_conf
        exit 0
    fi

    if [ "$PUSH" = true ]; then
        push_conf
        echo "Restarting consul containers..."
        bash "$script_dir/command_on_nodes.sh" -u "$SSH_USER" -nt $nodes_type -c "sudo $CONTAINER_ENGINE restart consul"
    fi

    cat_conf
}

# Run main function
main "$@"