#!/bin/bash

# Script to check container states on nodes
# Supports Docker and Podman container engines

script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_nodes_list_script="get_nodes_list.sh"
default_ssh_user="root"
default_container_engine="docker"
virtual_stands_mark="[NOTE] for virtual stands"
#script_name=$(basename "$0")

# Colors
normal=$(tput sgr0)
blue=$(tput setaf 4)
yellow=$(tput setaf 3)
red=$(tput setaf 1)

# Required container lists
ctrl_required_container_list=(
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
    "prometheus_server"
)
#    "prometheus_rabbitmq_exporter"

comp_required_container_list=(
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
    "prometheus_blackbox_exporter"
    "cron"
    "fluentd"
)

# Default values
[[ -z $CONTAINER_NAME ]] && CONTAINER_NAME=""
[[ -z $NODES ]] && NODES=()
[[ -z $NODES_TYPE ]] && NODES_TYPE="all"
[[ -z $NODES_NAME ]] && NODES_NAME=""
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $SSH_USER ]] && SSH_USER=""
[[ -z $CONTAINER_ENGINE ]] && CONTAINER_ENGINE="$default_container_engine"

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -nt, -type_of_nodes <type>    Node type: 'all', 'ctrl', 'comp', 'net', 'awn'
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

# Function to check required containers on a node
check_required_containers() {
    local node_ip="$1"
    local node_type="$2"

    echo -e "Checking required containers on $node_ip ($node_type)"

    local container_names
    container_names=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
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
                # Если контейнер в формате image:tag
                if [ -n "$container_required_note" ]; then
                    echo "$container_required_note"
                    echo -e "${yellow}Container $container_required not running - Warning${normal}"
                else
                    echo -e "${yellow}Container $container_required not running - Warning${normal}"
                fi
            else
                # Если контейнер не в формате image:tag
                if [ -n "$container_required_note" ]; then
                    echo "$container_required_note"
                    echo -e "${red}Container $container_required not running - ERROR${normal}"
                else
                    echo -e "${red}Container $container_required not running - ERROR${normal}"
                fi
            fi
        fi
    done
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

# Function to check container status on a node
check_container_status() {
    local node_name="$1"
    local node_ip="$2"

    echo -e "${blue}Checking containers on $node_name ($node_ip)${normal}"

    local format_option=""
    if [ "$CONTAINER_ENGINE" = "podman" ]; then
        format_option="--format 'table {{.ID}}\t{{.Image}}\t{{.Created}}\t{{.Status}}\t{{.Names}}'"
    fi

    ssh -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" \
        "sudo $CONTAINER_ENGINE ps -a $format_option" 2>/dev/null | \
        sed --unbuffered \
            -e 's/\(.*(unhealthy).*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*Exited.*\)/\o033[31m\1\o033[39m/' \
            -e 's/\(.*second.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*Less than.*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*(healthy).*\)/\o033[92m\1\o033[39m/' \
            -e 's/\(.*days.*\)/\o033[92m\1\o033[39m/' \
            -e 's/\(.*About an hour.*\)/\o033[92m\1\o033[39m/' \
            -e 's/\(.*minutes.*\)/\o033[92m\1\o033[39m/' \
            -e 's/\(.*weeks.*\)/\o033[92m\1\o033[39m/' \
            -e 's/\(.*hours.*\)/\o033[92m\1\o033[39m/' \
            -e 's/\(.*starting).*\)/\o033[33m\1\o033[39m/' \
            -e 's/\(.*restarting.*\)/\o033[31m\1\o033[39m/'
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


# Main execution

# Determine SSH user
get_ssh_user

# Get nodes list
if [ -n "$NODES_NAME" ]; then
    nodes=$(get_nodes_list -nn "$NODES_NAME")
else
    nodes=$(get_nodes_list -nt "$NODES_TYPE")
fi

if [ "$TS_DEBUG" = true ]; then
    get_nodes_list -nn "$NODES_NAME"
    get_nodes_list -nt "$NODES_TYPE"
    echo -e "
    [DEBUG] nodes: $nodes
    "
fi

IFS=' ' read -ra NODES <<< "$nodes"

[ "$TS_DEBUG" = true ] && echo -e "[DEBUG] Nodes: ${NODES[*]}"

# Process each node
for node_pair in "${NODES[@]}"; do
    # Split node:ip format
    node_name="${node_pair%%:*}"
    node_ip="${node_pair#*:}"

    # Check container status
    check_container_status "$node_name" "$node_ip"

    # Determine node type and check required containers
    if [ -z "$CONTAINER_NAME" ]; then
#        local node_type
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