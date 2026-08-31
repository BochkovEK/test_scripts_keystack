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
DEFAULT_SSH_KEY="${SSH_KEY_PATH:-}"
DEFAULT_JUMP_HOST="${JUMP_HOST:-}"
DEFAULT_JUMP_HOST_USER="${JUMP_HOST_USER:-$(whoami)}"
DEFAULT_JUMP_HOST_KEY="${JUMP_HOST_KEY:-${STAND_DIR_ENV:+$STAND_DIR_ENV/id_rsa}}"

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS] <node_ip> [node_name]"
    echo "       Or source this script and call test_ssh_connection function"
    echo ""
    echo "Options:"
    echo "  -u, --user <username>    SSH username (default: $DEFAULT_SSH_USER)"
    echo "  -t, --timeout <seconds>  SSH connection timeout (default: $DEFAULT_TIMEOUT)"
    echo "  -k, --key <key_path>     Path to SSH private key (default: auto-detect)"
    echo "  -jh, --jump-host <host>       Jump host (bastion) IP or FQDN to hop through via SSH ProxyCommand"
    echo "  -jhu, --jump-host-user <u>    User for the jump host login (default: current user, \$(whoami))"
    echo "  -jhk, --jump-host-key <path>  SSH private key for the jump host login"
    echo "                                (default: \$STAND_DIR_ENV/id_rsa, if STAND_DIR_ENV is set)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 my-server"
    echo "  $0 -u kolla -t 15 192.168.1.100"
    echo "  $0 -k /path/to/key.pem 192.168.1.100"
    echo "  $0 -k /path/to/key.pem -jh bastion.example.com -jhu root -jhk /root/.ssh/id_rsa 10.224.135.37"
    echo "  source ./ssh_test.sh && test_ssh_connection my-server 192.168.1.100 10 kolla /path/to/key.pem bastion.example.com root /root/.ssh/id_rsa"
}

# Standalone SSH check function that can be used independently
# Args: node_name node_ip [timeout] [ssh_user] [ssh_key] [jump_host] [jump_host_user] [jump_host_key]
test_ssh_connection() {
    local node_name="$1"
    local node_ip="$2"
    local timeout="${3:-$DEFAULT_TIMEOUT}"
    local ssh_user="${4:-$DEFAULT_SSH_USER}"
    local ssh_key="${5:-$DEFAULT_SSH_KEY}"
    local jump_host="${6:-$DEFAULT_JUMP_HOST}"
    local jump_host_user="${7:-$DEFAULT_JUMP_HOST_USER}"
    local jump_host_key="${8:-$DEFAULT_JUMP_HOST_KEY}"

    # If no parameters provided and running standalone, show help
    if [ $# -eq 0 ] && [ "$0" = "$BASH_SOURCE" ]; then
        show_help
        return 1
    fi

    echo -e "Testing SSH connection as $ssh_user to ${node_name:-$node_ip}$( [ -n "$jump_host" ] && echo " (via jump host $jump_host)" )..."

    # Check if required variables are set
    if [ -z "$ssh_user" ]; then
        echo -e "${red}SSH_USER variable is not set${normal}"
        return 1
    fi

    if [ -z "$node_ip" ]; then
        echo -e "${red}Node IP is not specified${normal}"
        return 1
    fi

    # If a jump host is requested, validate its key up front
    local jump_opts=()
    if [ -n "$jump_host" ]; then
        if [ -z "$jump_host_key" ]; then
            echo -e "${red}Jump host is set but no jump host key is configured (use -jhk or set STAND_DIR_ENV)${normal}"
            return 1
        fi
        if [ ! -f "$jump_host_key" ]; then
            echo -e "${red}Jump host SSH key not found: $jump_host_key${normal}"
            return 1
        fi
        jump_opts=(-o "ProxyCommand=ssh -i $jump_host_key -W %h:%p $jump_host_user@$jump_host")
    fi

    # Build SSH command with optional key
    local ssh_cmd="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$timeout -o BatchMode=yes"

    if [ -n "$ssh_key" ] && [ -f "$ssh_key" ]; then
        ssh_cmd="$ssh_cmd -i $ssh_key"
        echo -e "${blue}Using SSH key: $ssh_key${normal}"
    elif [ -n "$ssh_key" ] && [ ! -f "$ssh_key" ]; then
        echo -e "${yellow}⚠ SSH key not found: $ssh_key, using default authentication${normal}"
    fi

    # Test basic connectivity with ping first (optional, advisory only).
    # If a jump host is set, ping FROM the jump host, since the target
    # network may not be reachable directly from this machine - a failed
    # ping never blocks the following SSH check.
    if [ -n "$jump_host" ]; then
        if [ -n "$jump_host_key" ] && [ -f "$jump_host_key" ]; then
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout="$timeout" -i "$jump_host_key" \
                "$jump_host_user@$jump_host" "ping -c 1 -W 2 $node_ip" &> /dev/null; then
                echo -e "✓ Host $node_ip is reachable (via jump host $jump_host)"
            else
                echo -e "${yellow}⚠ Host $node_ip is not responding to ping (via jump host $jump_host)${normal}"
            fi
        fi
    elif command -v ping &> /dev/null; then
        if ping -c 1 -W 2 "$node_ip" &> /dev/null; then
            echo -e "✓ Host $node_ip is reachable"
        else
            echo -e "${yellow}⚠ Host $node_ip is not responding to ping${normal}"
        fi
    fi

    # Test SSH connection (with ProxyCommand jump_opts if a jump host is set)
    local ssh_output
    ssh_output=$($ssh_cmd "${jump_opts[@]}" "$ssh_user@$node_ip" "echo 'SUCCESS'; whoami; hostname" 2>&1)

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
        if [ -n "$jump_host" ]; then
            echo -e "${yellow}  Debug: Connection was attempted via jump host: $jump_host_user@$jump_host (key: $jump_host_key)${normal}"
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
    local jump_host="$DEFAULT_JUMP_HOST"
    local jump_host_user="$DEFAULT_JUMP_HOST_USER"
    local jump_host_key="$DEFAULT_JUMP_HOST_KEY"

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
            -jh|--jump-host)
                jump_host="$2"
                shift 2
                ;;
            -jhu|--jump-host-user)
                jump_host_user="$2"
                shift 2
                ;;
            -jhk|--jump-host-key)
                jump_host_key="$2"
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
    test_ssh_connection "$node_name" "$node_ip" "$timeout" "$ssh_user" "$ssh_key" "$jump_host" "$jump_host_user" "$jump_host_key"
}

# If script is executed directly (not sourced), parse arguments
if [ "$0" = "$BASH_SOURCE" ]; then
    parse_arguments "$@"
fi
