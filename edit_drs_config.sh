#!/bin/bash

# Script for managing DRS configuration files across controller nodes
# Supports pulling, pushing, and checking configuration files

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 6)


# Script paths
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
get_ssh_user_script="get_ssh_user.sh"
default_container_engine="docker"
default_ssh_user="root"

# Service and path configuration
service_name="drs"
nodes_type="ctrl"
test_node_conf_dir="kolla/$service_name"
conf_dir="/etc/kolla/$service_name"
conf_name="drs.ini"

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
)

# Default values
[[ -z $ADD_DEBUG ]] && ADD_DEBUG=false
[[ -z $TS_DEBUG ]] && TS_DEBUG=false
[[ -z $ONLY_CONF_CHECK ]] && ONLY_CONF_CHECK=false
[[ -z $ADD_PROM_ALERT ]] && ADD_PROM_ALERT=false
[[ -z $PROMETHEUS_PASS ]] && PROMETHEUS_PASS=""
[[ -z $PUSH ]] && PUSH=false
[[ -z $PULL ]] && PULL=false
[[ -z $CONF_NAME ]] && CONF_NAME="$conf_name"
[[ -z $CONTAINER_ENGINE ]] && CONTAINER_ENGINE=$default_container_engine
[[ -z $VIRTUAL_ENV ]] && VIRTUAL_ENV="$script_dir"

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

# Function to display configuration files
cat_conf() {
    local nodes="$1"
    echo "Displaying all $service_name configurations..."

    for node in $nodes; do
        local node_name="${node%%:*}"
        local node_ip="${node#*:}"
        echo -e "${cyan}Configuration on $node_name:${normal}"
        ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
            "sudo cat $conf_dir/$CONF_NAME 2>/dev/null || echo 'Configuration file not found'"
    done
}

# Function to pull configuration from controller node
pull_conf() {
    local nodes="$1"
    echo "Pulling $CONF_NAME from controller node..."

    # Create local directory if it doesn't exist
    [ ! -d "$VIRTUAL_ENV/$test_node_conf_dir" ] && mkdir -p "$VIRTUAL_ENV/$test_node_conf_dir"

    local first_node
    first_node=$(echo "$nodes" | awk '{print $1}')  # ← Используем переданный список

    if [ -z "$first_node" ]; then
        echo -e "${red}No controller nodes found${normal}"
        exit 1
    fi

    local node_name="${first_node%%:*}"
    local node_ip="${first_node#*:}"

    echo "Copying $service_name configuration from $node_name:$conf_dir/$CONF_NAME"

    # Copy configuration file
    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo cat $conf_dir/$CONF_NAME" > "$VIRTUAL_ENV/$test_node_conf_dir/${CONF_NAME}"

    # Create backup if it doesn't exist
    [ ! -f "$VIRTUAL_ENV/$test_node_conf_dir/${CONF_NAME}_backup" ] && \
        cp "$VIRTUAL_ENV/$test_node_conf_dir/${CONF_NAME}" "$VIRTUAL_ENV/$test_node_conf_dir/${CONF_NAME}_backup"

    echo -e "
To edit the configuration:
  vi $VIRTUAL_ENV/$test_node_conf_dir/$CONF_NAME

To apply the configuration:
  bash $script_dir/$(basename "$0") -push
"
}

# Function to push configuration to controller nodes
push_conf() {
    local nodes="$1"
    echo "Pushing $CONF_NAME to controller nodes..."

    if [ ! -f "$VIRTUAL_ENV/$test_node_conf_dir/$CONF_NAME" ]; then
        echo -e "${red}Configuration file not found: $VIRTUAL_ENV/$test_node_conf_dir/$CONF_NAME${normal}"
        exit 1
    fi

    for node in $nodes; do  # ← Используем переданный список
        local node_name="${node%%:*}"
        local node_ip="${node#*:}"

        echo "Pushing configuration to $node_name"

        if [ -n "$node_ip" ]; then
            # ... остальной код без изменений
        fi
    done
}

# Function to add debug logging
add_debug_logging() {
    echo "Adding debug logging to DRS configuration..."

    if [ ! -f "$VIRTUAL_ENV/$test_node_conf_dir/$CONF_NAME" ]; then
        echo -e "${yellow}Configuration file not found locally, pulling first...${normal}"
        pull_conf
    fi

    # Add debug setting
    sed -i 's/\[DEFAULT\]/\[DEFAULT\]\ndebug = true/' "$VIRTUAL_ENV/$test_node_conf_dir/$CONF_NAME"
    echo -e "${green}Debug logging enabled in local configuration${normal}"
}

# Function to add Prometheus alerting
add_prometheus_alerting() {
    echo "Adding Prometheus alerting to DRS configuration..."

    if [ -z "$PROMETHEUS_PASS" ]; then
        echo -e "${red}Prometheus password not provided${normal}"
        return 1
    fi

    if [ ! -f "$VIRTUAL_ENV/$test_node_conf_dir/$CONF_NAME" ]; then
        echo -e "${yellow}Configuration file not found locally, pulling first...${normal}"
        pull_conf
    fi

    # Check if Prometheus settings already exist
    local prom_pass_exists
    prom_pass_exists=$(grep 'prometheus_alert_manager_password' "$VIRTUAL_ENV/$test_node_conf_dir/$CONF_NAME")

    if [ -z "$prom_pass_exists" ]; then
        # Add Prometheus alerting settings
        sed -i "
            s/\[alerting\]/\[alerting\]\nenable_prometheus_alert_manager_auth = true\nprometheus_alert_manager_user = admin\nprometheus_alert_manager_password = $PROMETHEUS_PASS/
            s/enable_alerting = false/enable_alerting = true/
        " "$VIRTUAL_ENV/$test_node_conf_dir/$CONF_NAME"

        echo -e "${green}Prometheus alerting enabled in local configuration${normal}"
    else
        echo -e "${yellow}Prometheus alerting already configured${normal}"
    fi
}

# Main execution function
main() {
    parse_arguments "$@"
    load_external_scripts

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi

    echo -e "Using SSH user: $SSH_USER"

    # Get nodes list ONCE and reuse it
    if ! NODES=$(get_nodes_list -nt "$nodes_type"); then
        exit 1
    fi

    [ "$TS_DEBUG" = true ] && echo -e "${blue}[DEBUG] Nodes: $NODES${normal}"

    local config_changed=false

    # Execute requested actions
    if [ "$ONLY_CONF_CHECK" = true ]; then
        cat_conf "$NODES"
        exit 0
    fi

    if [ "$PULL" = true ]; then
        pull_conf "$NODES"
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
        push_conf "$NODES"
        config_changed=true
    fi

    if [ "$config_changed" = true ]; then
        # Show configuration after changes
        cat_conf "$NODES"

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