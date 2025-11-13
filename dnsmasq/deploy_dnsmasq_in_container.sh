#!/bin/bash

# Default values
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
get_ssh_user_script="get_ssh_user.sh"
check_ssh_connectivity_script="check_ssh_connectivity.sh"
default_ssh_user="root"
default_container_engine="docker"
default_action="start"

# External scripts array
external_scripts=(
    "$utils_dir/$get_ssh_user_script"
    "$utils_dir/$check_ssh_connectivity_script"
)

# Colors
normal=$(tput sgr0)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
cyan=$(tput setaf 6)

# Default values
[[ -z $CONTAINER_ENGINE ]] && CONTAINER_ENGINE="$default_container_engine"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $SSH_USER ]] && SSH_USER=""
[[ -z $IPS_LIST ]] && IPS_LIST=""
[[ -z $DNS_SERVER_IP ]] && DNS_SERVER_IP=""
[[ -z $ACTION ]] && ACTION=$default_action

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--ips)
                IPS_LIST="$2"
                shift 2
                ;;
            -d|--dns)
                DNS_SERVER_IP="$2"
                shift 2
                ;;
            -h|--help)
                help
                exit 0
                ;;
            start|stop)
                ACTION="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                help
                exit 1
                ;;
        esac
    done
}

help() {
    echo "Usage: $0 [OPTIONS] <start|stop>"
    echo
    echo "Options:"
    echo "  -i, --ips LIST          Comma-separated list of target host IPs (required for start)"
    echo "  -d, --dns IP            DNS server IP address (required for start)"
    echo "  -h, --help              Show this help message"
    echo
    echo "Environment variables:"
    echo "  SSH_USER                SSH username for remote hosts"
    echo "  CONTAINER_ENGINE        Container engine (docker/podman, default: podman)"
    echo
    echo "Examples:"
    echo "  $0 --ips 192.168.1.10,192.168.1.11 --dns 10.0.0.100 start"
    echo "  $0 stop"
    echo "  CONTAINER_ENGINE=docker $0 --ips 192.168.1.10 --dns 10.0.0.100 start"
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

# Function to validate inputs
validate_inputs() {
    # For start action, check required parameters
    if [[ "$ACTION" == "start" ]]; then
        if [[ -z "$IPS_LIST" ]]; then
            echo -e "${red}Error: IPS_LIST is required for start action${normal}"
            echo -e "${yellow}Use --ips option or set IPS_LIST environment variable${normal}"
            exit 1
        fi

        if [[ -z "$DNS_SERVER_IP" ]]; then
            echo -e "${red}Error: DNS_SERVER_IP is required for start action${normal}"
            echo -e "${yellow}Use --dns option or set DNS_SERVER_IP environment variable${normal}"
            exit 1
        fi
    fi

    # Validate container engine
    if [[ "$CONTAINER_ENGINE" != "docker" && "$CONTAINER_ENGINE" != "podman" ]]; then
        echo -e "${red}Error: CONTAINER_ENGINE must be 'docker' or 'podman'${normal}"
        exit 1
    fi
}

# Function to check SSH connectivity to a node
check_ssh_connectivity() {
    local node_ip=$1

    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_USER@$node_ip" "exit" > /dev/null 2>&1; then
        echo -e "✓ SSH connection successful to $node_ip"
        return 0
    else
        echo -e "${red}✗ SSH connection failed to $node_ip${normal}"
        return 1
    fi
}

# Function to check and setup dnsmasq.conf
setup_dnsmasq_config() {
    local config_file="$script_dir/dnsmasq.conf"
    local template_file="$script_dir/dnsmasq.conf.template"

    if [[ -f "$config_file" ]]; then
        echo -e "${cyan}✓ dnsmasq.conf found${normal}"
        return 0
    fi

    echo -e "${yellow}dnsmasq.conf not found${normal}"

    if [[ -f "$template_file" ]]; then
        echo -e "${cyan}Copying template to dnsmasq.conf...${normal}"
        cp "$template_file" "$config_file"
        echo -e "${yellow}Please edit $config_file and add your DNS entries in format:${normal}"
        echo -e "${yellow}address=/hostname.example.com/192.168.1.100${normal}"
        exit 1
    else
        echo -e "${red}Error: Neither dnsmasq.conf nor template found${normal}"
        echo -e "${yellow}Create $config_file with your DNS entries:${normal}"
        echo -e "${cyan}Example content:"
        echo "address=/hostname1.example.com/192.168.1.100"
        echo "address=/hostname2.example.com/192.168.1.101"
        echo "server=8.8.8.8"
        echo "server=8.8.4.4"
        echo -e "${normal}"
        exit 1
    fi
}

prepare_docker_compose() {
    local temp_file="$script_dir/docker-compose.temp.yml"

    sed "s|\./dnsmasq.conf|\${COMPOSE_PROJECT_DIR}/dnsmasq.conf|g" \
        "$script_dir/docker-compose.yml" > "$temp_file"

    echo "$temp_file"
}

edit_resolv() {
    local node_ip=$1
    echo -e "${yellow}Updating resolv.conf on $node_ip${normal}"

    ssh "$SSH_USER@$node_ip" "
        # Backup original resolv.conf
        cp /etc/resolv.conf /etc/resolv.conf.backup && \
        # Create new resolv.conf with only our DNS server
        echo -e \"# Custom DNS (dnsmasq) server\\nnameserver $DNS_SERVER_IP\" > /etc/resolv.conf
    "
}

start_service() {
    echo -e "${cyan}Starting DNSMASQ service...${normal}"

    # Check if dnsmasq.conf exists
    setup_dnsmasq_config

    local compose_file
    compose_file=$(prepare_docker_compose)

    export COMPOSE_PROJECT_DIR="$script_dir"

    if ! $CONTAINER_ENGINE compose -f "$compose_file" up -d; then
        echo -e "${red}Error: Failed to start DNSMASQ container${normal}"
        rm -f "$compose_file"
        exit 1
    fi

    rm -f "$compose_file"

    echo -e "${cyan}Configuring DNS on remote hosts...${normal}"

    # Convert comma-separated list to array
    IFS=',' read -ra NODES <<< "$IPS_LIST"

    for node_ip in "${NODES[@]}"; do
        echo -e "${cyan}Configuring $node_ip...${normal}"

        # Check SSH connectivity first
        if ! check_ssh_connectivity "$node_ip"; then
            continue
        fi

        # Check if DNS server IP already exists in resolv.conf
        if ! ssh "$SSH_USER@$node_ip" "grep -q '$DNS_SERVER_IP' /etc/resolv.conf" 2>/dev/null; then
            edit_resolv "$node_ip"

            if [[ $? -eq 0 ]]; then
                echo -e "${cyan}✓ DNS configured successfully on $node_ip${normal}"
            else
                echo -e "${red}✗ Failed to configure DNS on $node_ip${normal}"
            fi
        else
            echo -e "${cyan}✓ DNS server already configured on $node_ip${normal}"
        fi
    done
}

stop_service() {
    echo -e "${cyan}Stopping DNSMASQ service...${normal}"

    if ! $CONTAINER_ENGINE compose -f "$script_dir/docker-compose.yml" down; then
        echo -e "${red}Error: Failed to stop DNSMASQ container${normal}"
        exit 1
    fi

    echo -e "${cyan}Stopping system DNS services...${normal}"

    # Find and stop system DNS services related to container engine
    local dns_services
    dns_services=$(sudo systemctl | grep "$CONTAINER_ENGINE.*dns" | awk '{print $1}')

    if [[ -n "$dns_services" ]]; then
        echo -e "${yellow}Stopping DNS services: $dns_services${normal}"
        sudo systemctl stop $dns_services
        echo -e "${cyan}✓ DNS services stopped successfully${normal}"
    else
        echo -e "${cyan}No DNS services found to stop${normal}"
    fi

    echo -e "${cyan}✓ DNSMASQ service stopped successfully${normal}"
}

# Main
main() {
    # Load external scripts first
    load_external_scripts

    # Determine SSH user using external function
    SSH_USER=$(get_and_validate_ssh_user "$SSH_USER" "$default_ssh_user")
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Error: Failed to determine valid SSH user!${normal}"
        exit 1
    fi

    # Parse command line arguments
    parse_arguments "$@"

    # Validate inputs
    validate_inputs

    # Execute the requested action
    case "$ACTION" in
        "start")
            start_service
            ;;
        "stop")
            stop_service
            ;;
        *)
            echo -e "${red}Error: Unknown action '$ACTION'${normal}"
            help
            exit 1
            ;;
    esac

    echo -e "${cyan}Operation completed successfully${normal}"
}

# Run main function with all arguments
main "$@"