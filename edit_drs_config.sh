#!/bin/bash

# Script for managing DRS configuration files across controller nodes
# Supports pulling, pushing, and checking configuration files

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
cyan=$(tput setaf 14)
#violet=$(tput setaf 5)

# Service and path configuration
service_name="drs"
nodes_type="ctrl"
test_node_conf_dir="kolla/$service_name"
conf_dir="/etc/kolla/$service_name"
conf_name="drs.ini"

# Script paths
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
default_ssh_user="root"
#install_package_script="install_package.sh"

# Default values
ADD_DEBUG="${ADD_DEBUG:-false}"
TS_DEBUG="${TS_DEBUG:-false}"
ONLY_CONF_CHECK="${ONLY_CONF_CHECK:-false}"
ADD_PROM_ALERT="${ADD_PROM_ALERT:-false}"
PROMETHEUS_PASS="${PROMETHEUS_PASS:-}"
PUSH="${PUSH:-false}"
PULL="${PULL:-false}"
CONF_NAME="${CONF_NAME:-$conf_name}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Manage DRS configuration files across controller nodes.

    Options:
      -v, -debug                        Enable debug output
      -add_debug                        Add DEBUG level to DRS logs
      -pa, -prometheus_alerting <pass>  Enable Prometheus alerting with password
      -pull                             Pull configuration from controller node
      -push                             Push configuration to all controller nodes
      -check                            Only check configuration without changes
      -u, -ssh_user <user>              Set SSH user for remote access
      -ce, -container_engine <engine>   Container engine (docker/podman)

    Examples:
      # Check current configuration
      $0 -check

      # Pull configuration for editing
      $0 -pull

      # Push configuration changes
      $0 -push

      # Add debug logging
      $0 -add_debug -push

      # Enable Prometheus alerting
      $0 -pa mypassword -push
    "
}

# Function to get nodes list using external script
get_nodes_list() {
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*"

    local nodes_result=""
    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")

    [ "$TS_DEBUG" = true ] && echo -e "
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

# Parse command line arguments
parse_arguments() {
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
            -add_debug)
                ADD_DEBUG="true"
                echo "Debug logging will be enabled"
                shift
                ;;
            -pa|-prometheus_alerting)
                PROMETHEUS_PASS="$2"
                ADD_PROM_ALERT="true"
                echo "Prometheus alerting enabled with provided password"
                shift 2
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
            -u|-ssh_user)
                SSH_USER="$2"
                echo "Using SSH user: $SSH_USER"
                shift 2
                ;;
            -ce|-container_engine)
                CONTAINER_ENGINE="$2"
                echo "Using container engine: $CONTAINER_ENGINE"
                shift 2
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
    done
}

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

    # Create local directory if it doesn't exist
    [ ! -d "$script_dir/$test_node_conf_dir" ] && mkdir -p "$script_dir/$test_node_conf_dir"

    # Get nodes list
    local nodes
    nodes=$(get_nodes_list -nt "$nodes_type")
    local first_node
    first_node=$(echo "$nodes" | awk '{print $1}')

    if [ -z "$first_node" ]; then
        echo -e "${red}No controller nodes found${normal}"
        exit 1
    fi

    local node_name="${first_node%%:*}"
    local node_ip="${first_node#*:}"

    echo "Copying $service_name configuration from $node_name:$conf_dir/$CONF_NAME"

    # Copy configuration file
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo cat $conf_dir/$CONF_NAME" > "$script_dir/$test_node_conf_dir/${CONF_NAME}"

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

        # Get node IP for API host replacement
        local node_actual_ip
        node_actual_ip=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "hostname -I | awk '{print \$1}'" 2>/dev/null)

        if [ -n "$node_actual_ip" ]; then
            # Create temporary file with replaced IP addresses
            local temp_file
            temp_file=$(mktemp)

            # Replace API host IP
            sed -E "
                s/api_host[[:space:]]*=[[:space:]]*[0-9.]+[0-9]+/api_host = $node_actual_ip/g
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

# Function to add debug logging
add_debug_logging() {
    echo "Adding debug logging to DRS configuration..."

    if [ ! -f "$script_dir/$test_node_conf_dir/$CONF_NAME" ]; then
        echo -e "${yellow}Configuration file not found locally, pulling first...${normal}"
        pull_conf
    fi

    # Add debug setting
    sed -i 's/\[DEFAULT\]/\[DEFAULT\]\ndebug = true/' "$script_dir/$test_node_conf_dir/$CONF_NAME"
    echo -e "${green}Debug logging enabled in local configuration${normal}"
}

# Function to add Prometheus alerting
add_prometheus_alerting() {
    echo "Adding Prometheus alerting to DRS configuration..."

    if [ -z "$PROMETHEUS_PASS" ]; then
        echo -e "${red}Prometheus password not provided${normal}"
        return 1
    fi

    if [ ! -f "$script_dir/$test_node_conf_dir/$CONF_NAME" ]; then
        echo -e "${yellow}Configuration file not found locally, pulling first...${normal}"
        pull_conf
    fi

    # Check if Prometheus settings already exist
    local prom_pass_exists
    prom_pass_exists=$(grep 'prometheus_alert_manager_password' "$script_dir/$test_node_conf_dir/$CONF_NAME")

    if [ -z "$prom_pass_exists" ]; then
        # Add Prometheus alerting settings
        sed -i "
            s/\[alerting\]/\[alerting\]\nenable_prometheus_alert_manager_auth = true\nprometheus_alert_manager_user = admin\nprometheus_alert_manager_password = $PROMETHEUS_PASS/
            s/enable_alerting = false/enable_alerting = true/
        " "$script_dir/$test_node_conf_dir/$CONF_NAME"

        echo -e "${green}Prometheus alerting enabled in local configuration${normal}"
    else
        echo -e "${yellow}Prometheus alerting already configured${normal}"
    fi
}

# Main execution function
main() {
    parse_arguments "$@"
    determine_ssh_user

    local config_changed=false

    # Execute requested actions
    if [ "$ONLY_CONF_CHECK" = true ]; then
        cat_conf
        exit 0
    fi

    if [ "$PULL" = true ]; then
        pull_conf
        exit 0
    fi

    if [ "$ADD_DEBUG" = true ]; then
        add_debug_logging
        config_changed=true
    fi

    if [ "$ADD_PROM_ALERT" = true ]; then
        if add_prometheus_alerting; then
            config_changed=true
        fi
    fi

    if [ "$PUSH" = true ]; then
        push_conf
        config_changed=true
    fi

    if [ "$config_changed" = true ]; then
        # Show configuration after changes
        cat_conf

        # Restart DRS service if configuration was changed
        echo "Restarting $service_name containers..."
        bash "$script_dir/command_on_nodes.sh" -u "$SSH_USER" -nt ctrl \
            -c "sudo $CONTAINER_ENGINE restart $service_name"
    else
        echo -e "${yellow}No configuration changes were made${normal}"
    fi
}

# Run main function
main "$@"