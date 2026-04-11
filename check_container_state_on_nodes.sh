#!/bin/bash

# Script to check container states on nodes
# Supports Docker and Podman container engines

# Colors
normal=$(tput sgr0)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
cyan=$(tput setaf 6)
#green=$(tput setaf 2)

script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
get_ssh_user_script="get_ssh_user.sh"
check_ssh_connectivity_script="check_ssh_connectivity.sh"
default_ssh_user="root"
default_container_engine="docker"
default_ks_release="ks-2025.2.5"
virtual_stands_mark="[NOTE] required for virtual stands"
#script_name=$(basename "$0")

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
    "$utils_dir/$check_ssh_connectivity_script"
)

# Required container lists
default_ctrl_required_container_list=(
    "keystone"
    "keystone_ssh"
    "rabbitmq"
    "memcached"
    "mariadb"
    "redis"
    "haproxy"
    "horizon"
    "nova_serialproxy"
    "nova_novncproxy"
    "nova_conductor"
    "nova_api"
    "nova_scheduler"
    "placement_api"
    "cinder_volume"
    "cinder_scheduler"
    "cinder_api"
    "adminui_frontend"
    "adminui_backend"
    "drs"
    "consul"
    "prometheus_consul_exporter"
    "prometheus_blackbox_exporter"
    "prometheus_elasticsearch_exporter"
    "prometheus_openstack_exporter"
    "prometheus_alertmanager"
    "prometheus_memcached_exporter"
    "prometheus_mysqld_exporter"
    "prometheus_node_exporter"
    "prometheus_server:[NOTE] alternative containers victoriametrics_vminsert, victoriametrics_vmselect, victoriametrics_vmagent"
)
#    "prometheus_rabbitmq_exporter"

default_comp_required_container_list=(
    "iscsid:$virtual_stands_mark"
    "consul"
    "neutron_openvswitch_agent"
    "openvswitch_vswitchd"
    "openvswitch_db"
    "nova_compute"
    "nova_libvirt"
    "nova_ssh"
    "prometheus_hypervisor_exporter"
    "prometheus_ovs_exporter"
    "prometheus_libvirt_exporter"
    "prometheus_node_exporter"
    "cron"
    "fluentd"
)
#    "prometheus_blackbox_exporter" remove from comp list (@chembaev telegram)

# Default values
[[ -z $CONTAINER_NAME ]] && CONTAINER_NAME=""
[[ -z $NODES ]] && NODES=()
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $SSH_USER ]] && SSH_USER=""
[[ -z $CONTAINER_ENGINE ]] && CONTAINER_ENGINE="$default_container_engine"
[[ -z $KS_RELEASE ]] && KS_RELEASE=$default_ks_release

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -nt, -type_of_nodes <type>    Node type: 'all', 'ctrl', 'comp', 'net', 'strg'
      -nn, -node_name <names>       Space-separated node names
      -u, -user <username>          SSH username
      -ce, -container_engine <engine>  Container engine: docker or podman
      -debug                        Enable debug output
      --help                        Show this help message
    "
}

# Function to define parameters from positional arguments
define_parameters() {
    [ "$count" = 1 ] && [[ -n $1 ]] && {
        echo "Parameter found: $1"
    }
}

# Parse command line arguments
count=1
while [ -n "$1" ]; do
    case "$1" in
        --help)
            show_help
            exit 0
            ;;

        -nt|-type_of_nodes)
            NODES_TYPE="$2"
            echo "Found -type_of_nodes with value: $NODES_TYPE"
            shift
            ;;

        -nn|-node_name)
            NODES_NAME="$2"
            echo "Found -node_name with value: $NODES_NAME"
            shift
            ;;

        -ce|-container_engine)
            CONTAINER_ENGINE="$2"
            echo "Found -docker_engine with value: $CONTAINER_ENGINE"
            shift
            ;;

        -u|-user)
            SSH_USER="$2"
            echo "Found -user with value: $SSH_USER"
            shift
            ;;

        -k|-key_path)
            KEY_PATH="$2"
            echo "Found -key_path with value: $KEY_PATH"
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
            echo "Parameter #$count: $1"
            define_parameters "$1"
            count=$((count + 1))
            ;;
    esac
    shift
done

# Function to find and load container config
load_container_config() {
    local config_pattern=".container_set_$KS_RELEASE" # .container_set_ks_2025.2.5
    local config_files=()

    # Find all matching config files
    while IFS= read -r -d $'\0' file; do
        config_files+=("$file")
    done < <(find "$script_dir" -maxdepth 1 -name "$config_pattern" -type f -print0)

    if [ ${#config_files[@]} -eq 0 ]; then
        echo -e "${yellow}Warning: No container config files found matching pattern: $config_pattern${normal}"
        # Set default lists if no config found
        ctrl_required_container_list=("${default_ctrl_required_container_list[@]}")
        comp_required_container_list=("${default_comp_required_container_list[@]}")
        return 1
    elif [ ${#config_files[@]} -eq 1 ]; then
        # Only one config file found, use it
        load_container_lists_from_config "${config_files[0]}"
        return $?
    else
        # Multiple config files found, use the first one and show warning
        echo -e "${yellow}Warning: Multiple container config files found, using: $(basename "${config_files[0]}")${normal}"
        load_container_lists_from_config "${config_files[0]}"
        return $?
    fi
}

# Function to load container lists from config file
load_container_lists_from_config() {
    local config_file="$1"
    local config_name=$(basename "$config_file")

    if [ ! -f "$config_file" ]; then
        echo -e "${red}Error: Container config file not found: $config_file${normal}"
        return 1
    fi

    echo "Container set obtained from config: $config_name"

    # Clear existing arrays
    ctrl_required_container_list=()
    comp_required_container_list=()

    # Parse config file
    local current_section=""
    while IFS= read -r line || [ -n "$line" ]; do
        # Remove leading/trailing whitespace and comments
        line=$(echo "$line" | sed 's/#.*$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

        # Skip empty lines
        [ -z "$line" ] && continue

        # Check for section headers
        if [[ "$line" == "[ctrl]" ]]; then
            current_section="ctrl"
            continue
        elif [[ "$line" == "[comp]" ]]; then
            current_section="comp"
            continue
        fi

        # Add to appropriate array based on current section
        if [ "$current_section" = "ctrl" ]; then
            ctrl_required_container_list+=("$line")
        elif [ "$current_section" = "comp" ]; then
            comp_required_container_list+=("$line")
        fi
    done < "$config_file"

    if [ "$TS_DEBUG" = true ]; then
        echo -e "[DEBUG] Loaded CTRL containers: ${ctrl_required_container_list[*]}"
        echo -e "[DEBUG] Loaded COMP containers: ${comp_required_container_list[*]}"
    fi

    return 0
}

# Function to check required containers on a node
check_required_containers() {
    local node_ip="$1"
    local node_type="$2"
    local check_succeeded=true

    echo -e "Checking required containers on $node_ip ($node_type)"

     if [ -n "$KEY_PATH" ]; then
        KEY_STRING="-i $KEY_PATH"
        [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] KEY_STRING: $KEY_STRING
    " >&2
    fi

    local container_names
    container_names=$(ssh -o StrictHostKeyChecking=no "$KEY_STRING" "$SSH_USER@$node_ip" \
        "sudo $CONTAINER_ENGINE ps --format '{{.Names}}' --filter status=running" 2>/dev/null)

    local required_containers=()
    case "$node_type" in
        ctrl) required_containers=("${ctrl_required_container_list[@]}") ;;
        comp) required_containers=("${comp_required_container_list[@]}") ;;
        *) return ;;
    esac

    for container_required in "${required_containers[@]}"; do
        local container_exists="false"
        local container_required_name="${container_required%%:*}"

        for container in $container_names; do
            [ "$TS_DEBUG" = true ] && echo -e "
[DEBUG] Container: $container, Required: container_required_name"

            if [ "$container" = "$container_required_name" ]; then
                container_exists="true"
                break
            fi
        done

        if [ "$container_exists" = "false" ]; then
            local container_required_note="${container_required#*:}"
            if [[ "$container_required" == *:* ]]; then
                if [ -n "$container_required_note" ]; then
                    echo -e "${yellow}[Warning] Container $container_required_name not running $container_required_note${normal}"
                fi
            else
                echo -e "${red}[ERROR] - Container $container_required not running${normal}"
                check_succeeded=false
            fi
        fi
    done

    if [ "$check_succeeded" = "true" ]; then
        echo "✓ Check of required containers completed successfully"
    fi
}

# Function to get nodes list using external script
get_nodes_list() {
    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
        Count parameters: $#
        Parameters: $*" >&2

    local nodes_result=""

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG]:
      nodes_result=\$(bash \"$utils_dir/$get_nodes_list_script\" \"$*\")" >&2

#    nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@")

    if ! nodes_result=$(bash "$utils_dir/$get_nodes_list_script" "$@" 2>&1); then
#        exit_code=$?
        echo -e "${red}ERROR: Node list script failed${normal}" >&2
        echo -e "${red}Output: $nodes_result${normal}" >&2
        return 1
    fi

    [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] nodes_result: $nodes_result
    " >&2

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

# Function to check SSH connectivity to a node
check_ssh_connectivity() {
    local node_pair=$1
    local node_name="${node_pair%%:*}"
    local node_ip="${node_pair#*:}"

    if test_ssh_connection "$node_name" "$node_ip" "10" "$SSH_USER" "$KEY_PATH" > /dev/null 2>&1; then
        echo -e "✓ SSH connection successful"
        return 0
    else
        echo -e "${red}✗ SSH connection failed${normal}"
        return 1
    fi
}

# Enhanced container status check with SSH connectivity verification
check_container_status() {
    local node_name="$1"
    local node_ip="$2"

    echo -e "${cyan}Checking containers on $node_name ($node_ip)${normal}"

    local format_option=""
    if [ "$CONTAINER_ENGINE" = "podman" ]; then
        format_option="--format 'table {{.ID}}\t{{.Image}}\t{{.Created}}\t{{.Status}}\t{{.Names}}'"
    fi

    if [ -n "$KEY_PATH" ]; then
        KEY_STRING="-i $KEY_PATH"
        [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] KEY_STRING: $KEY_STRING
    " >&2
    fi

     [ "$TS_DEBUG" = true ] && echo -e "
    [DEBUG] check container command string: ssh -o StrictHostKeyChecking=no $KEY_STRING $SSH_USER@$node_ip \
        \"sudo $CONTAINER_ENGINE ps -a $format_option\"
    " >&2

    # Now check containers since SSH is working
    ssh -o StrictHostKeyChecking=no "$KEY_STRING" "$SSH_USER@$node_ip" \
        "sudo $CONTAINER_ENGINE ps -a $format_option"  | \
        sed --unbuffered \
          -e 's/\(.*(unhealthy).*\)/\o033[31m\1\o033[39m/' \
          -e 's/\(.*Exited.*\)/\o033[31m\1\o033[39m/' \
          -e 's/\(.*Stopping.*\)/\o033[33m\1\o033[39m/' \
          -e 's/\(.*restarting.*\)/\o033[33m\1\o033[39m/' \
          -e 's/\(.*second.*\)/\o033[33m\1\o033[39m/' \
          -e 's/\(.*a minute.*\)/\o033[33m\1\o033[39m/' \
          -e 's/\(.*Less than.*\)/\o033[33m\1\o033[39m/' \
          -e 's/\(.*(healthy).*\)/\o033[92m\1\o033[39m/' \
          -e 's/\(.*days.*\)/\o033[92m\1\o033[39m/' \
          -e 's/\(.*About an hour.*\)/\o033[92m\1\o033[39m/' \
          -e 's/\(.*minutes.*\)/\o033[92m\1\o033[39m/' \
          -e 's/\(.*weeks.*\)/\o033[92m\1\o033[39m/' \
          -e 's/\(.*hours.*\)/\o033[92m\1\o033[39m/' \
          -e 's/\(.*months.*\)/\o033[92m\1\o033[39m/'
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
    # Load external scripts first
    load_external_scripts

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi

    # Load container configuration
    if ! load_container_config; then
        echo -e "${yellow}Using default container lists${normal}"
    fi

    echo -e "Using SSH user: $SSH_USER"

    # Get nodes list
    if [ -n "$NODES_NAME" ]; then
        nodes=$(get_nodes_list -nn "$NODES_NAME")
    else
        nodes=$(get_nodes_list -nt "$NODES_TYPE")
    fi

    if [ "$TS_DEBUG" = true ]; then
        echo -e "
    [DEBUG] nodes: $nodes
    "
    fi

    for node_pair in $nodes; do
        # Split node:ip format
        echo "$node_pair"
        node_name="${node_pair%%:*}"
        node_ip="${node_pair#*:}"

        # First check SSH connectivity
        if ! check_ssh_connectivity "$node_pair"; then
            echo -e "${red}Cannot check containers on $node_name - SSH connection failed${normal}"
            continue
        fi

        # Check container status
        check_container_status "$node_name" "$node_ip"

        # Determine node type and check required containers
        if [ -z "$CONTAINER_NAME" ]; then
            node_type=$(bash "$utils_dir/$get_nodes_list_script" -return_type "$node_name")

            [ "$TS_DEBUG" = true ] && echo -e "
[DEBUG] Node: $node_name, Type: $node_type"

            case "$node_type" in
                ctrl|comp)
                    check_required_containers "$node_ip" "$node_type"
                    ;;
            esac
        fi

        echo "----------------------------------------"
    done
}

main "$@"