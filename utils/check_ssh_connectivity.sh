#!/bin/bash

# Standalone SSH connection test script
# Can be used as a standalone script or sourced as a function

# Color definitions
normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
blue=$(tput setaf 6)

# Default values
DEFAULT_SSH_USER="${SSH_USER:-root}"
DEFAULT_TIMEOUT=10
DEFAULT_SSH_KEY="${SSH_KEY:-}"

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS] <node_ip> [node_name]"
    echo "       Or source this script and call test_ssh_connection function"
    echo ""
    echo "Options:"
    echo "  -u, --user <username>    SSH username (default: $DEFAULT_SSH_USER)"
    echo "  -t, --timeout <seconds>  SSH connection timeout (default: $DEFAULT_TIMEOUT)"
    echo "  -k, --key <key_path>     Path to SSH private key (default: auto-detect)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 my-server"
    echo "  $0 -u kolla -t 15 192.168.1.100"
    echo "  $0 -k /path/to/key.pem 192.168.1.100"
    echo "  source ./ssh_test.sh && test_ssh_connection my-server 192.168.1.100 10"
}

# Standalone SSH check function that can be used independently
test_ssh_connection() {
    local node_name="$1"
    local node_ip="$2"
    local timeout="${3:-$DEFAULT_TIMEOUT}"
    local ssh_user="${4:-$DEFAULT_SSH_USER}"
    local ssh_key="${5:-$DEFAULT_SSH_KEY}"

    # If no parameters provided and running standalone, show help
    if [ $# -eq 0 ] && [ "$0" = "$BASH_SOURCE" ]; then
        show_help
        return 1
    fi

    echo -e "Testing SSH connection as $remote_user to ${node_name:-$node_ip}..."

    # Check if required variables are set
    if [ -z "$ssh_user" ]; then
        echo -e "${red}SSH_USER variable is not set${normal}"
        return 1
    fi

    if [ -z "$node_ip" ]; then
        echo -e "${red}Node IP is not specified${normal}"
        return 1
    fi

    # Build SSH command with optional key
    local ssh_cmd="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$timeout -o BatchMode=yes"

    if [ -n "$ssh_key" ] && [ -f "$ssh_key" ]; then
        ssh_cmd="$ssh_cmd -i $ssh_key"
        echo -e "${blue}Using SSH key: $ssh_key${normal}"
    elif [ -n "$ssh_key" ] && [ ! -f "$ssh_key" ]; then
        echo -e "${yellow}⚠ SSH key not found: $ssh_key, using default authentication${normal}"
    fi

    ssh_cmd="$ssh_cmd $ssh_user@$node_ip"

    # Test basic connectivity with ping first (optional)
    if command -v ping &> /dev/null; then
        if ping -c 1 -W 2 "$node_ip" &> /dev/null; then
            echo -e "✓ Host $node_ip is reachable"
        else
            echo -e "${yellow}⚠ Host $node_ip is not responding to ping${normal}"
        fi
    fi

    # Test SSH connection
    local ssh_output
    ssh_output=$($ssh_cmd "echo 'SUCCESS'; whoami; hostname" 2>&1)

    local ssh_exit_code=$?

    if [ $ssh_exit_code -eq 0 ]; then
        local remote_user=$(echo "$ssh_output" | sed -n '2p')
        local remote_hostname=$(echo "$ssh_output" | sed -n '3p')
        echo -e "✓ SSH connection successful"
        return 0
    else
        echo -e "${red}✗ SSH connection failed${normal}"
        # Provide more detailed error information
        case $ssh_exit_code in
            255)
                echo -e "${red}  Error: Network connection refused or host unreachable${normal}"
                ;;
            5)
                echo -e "${red}  Error: Host key verification failed${normal}"
                ;;
            1)
                echo -e "${red}  Error: Authentication failed${normal}"
                ;;
            *)
                echo -e "${red}  Error: SSH connection failed (exit code: $ssh_exit_code)${normal}"
                ;;
        esac

        # Additional debug info if key was specified
        if [ -n "$ssh_key" ]; then
            echo -e "${yellow}  Debug: Key authentication was attempted with: $ssh_key${normal}"
        fi

        return 1
    fi
}

# Parse command line arguments when running as standalone script
parse_arguments() {
    local node_ip=""
    local node_name=""
    local ssh_user="$DEFAULT_SSH_USER"
    local timeout="$DEFAULT_TIMEOUT"
    local ssh_key="$DEFAULT_SSH_KEY"

    while [ $# -gt 0 ]; do
        case "$1" in
            -u|--user)
                ssh_user="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -k|--key)
                ssh_key="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [ -z "$node_ip" ]; then
                    node_ip="$1"
                elif [ -z "$node_name" ]; then
                    node_name="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$node_ip" ]; then
        echo "Error: Node IP is required"
        show_help
        exit 1
    fi

    # Call the function with parsed arguments
    test_ssh_connection "$node_name" "$node_ip" "$timeout" "$ssh_user" "$ssh_key"
}

# If script is executed directly (not sourced), parse arguments
if [ "$0" = "$BASH_SOURCE" ]; then
    parse_arguments "$@"
fi