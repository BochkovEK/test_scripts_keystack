#!/bin/bash

# Script to execute commands on VMs via SSH
# Supports execution on all VMs of a hypervisor or specific VMs by IP/name

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
cyan=$(tput setaf 14)

# Script configuration
script_name=$(basename "$0")
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
openstack_utils="$utils_dir/openstack"
default_ssh_timeout=5
get_vms_list_script="get_vms_list.sh"

# Default values
KEY_PATH="${KEY_PATH:-$script_dir/key_test.pem}"
OPENRC_PATH="${OPENRC_PATH:-$HOME/openrc}"
HYPERVISOR_NAME="${HYPERVISOR_NAME:-}"
ONLY_PING="${ONLY_PING:-false}"
ONLY_CHECK="${ONLY_CHECK:-false}"
VM_USER="${VM_USER:-ubuntu}"
COMMAND_STR="${COMMAND_STR:-ls -la}"
PROJECT="${PROJECT:-}"
DONT_ASK="${DONT_ASK:-true}"
TS_DEBUG="${TS_DEBUG:-false}"
VMS="${VMS:-}"
TS_SSH_TIMEOUT="${TS_SSH_TIMEOUT:-$default_ssh_timeout}"

# Function to display help information
show_help() {
    echo -e "
    Usage: $0 [OPTIONS]

    Execute commands on VMs via SSH. Can target all VMs on a hypervisor or specific VMs by IP.

    Options:
      -hv <name>              Hypervisor name
      -u, -user <username>    VM OS username (default: ubuntu)
      -c, -command <command>  Command to execute on VMs
      -k, -key <path>         SSH private key file path
      -ping                   Only perform ping check
      -p, -project <name>     OpenStack project name (default: admin)
      -dont_ask               Perform actions automatically without confirmation
      -vms                    Space-separated list of IP\name addresses
      -v, -debug              Enable debug output
      -check                  Only check SSH access without executing commands
      -t, -timeout <seconds>  SSH connection timeout (default: 5)
      --help                  Show this help message

    Examples:
      # Run command on all VMs of a hypervisor
      $0 -hv compute-01 -c 'df -h'

      # Check connectivity to specific VMs
      $0 -vms \"192.168.1.10 192.168.1.11\" -check
      $0 -vms \"vm_name1 vm_name2\" -check

      # Only ping check
      $0 -hv compute-01 -ping
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
            -hv)
                HYPERVISOR_NAME="$2"
                echo "Targeting hypervisor: $HYPERVISOR_NAME"
                shift 2
                ;;
            -u|-user)
                VM_USER="$2"
                echo "Using VM user: $VM_USER"
                shift 2
                ;;
            -c|-command)
                COMMAND_STR="$2"
                echo "Command to execute: $COMMAND_STR"
                shift 2
                ;;
            -k|-key)
                KEY_PATH="$2"
                echo "Using SSH key: $KEY_PATH"
                shift 2
                ;;
            -t|-timeout)
                TS_SSH_TIMEOUT="$2"
                echo "SSH timeout: $TS_SSH_TIMEOUT seconds"
                shift 2
                ;;
            -p|-project)
                PROJECT="$2"
                echo "OpenStack project: $PROJECT"
                shift 2
                ;;
            -ping)
                ONLY_PING="true"
                echo "Ping check only"
                shift
                ;;
            -check)
                ONLY_CHECK="true"
                echo "SSH access check only"
                shift
                ;;
            -dont_ask)
                DONT_ASK="true"
                echo "Automatic execution without confirmation"
                shift
                ;;
            -v|-debug)
                TS_DEBUG="true"
                echo "Debug mode enabled"
                shift
                ;;
            -vms)
                VMS="$2"
                echo "Targeting specific VMS: $VMS"
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

# Function to validate SSH key
validate_ssh_key() {
    if [ ! -f "$KEY_PATH" ]; then
        echo -e "${red}SSH key not found: $KEY_PATH${normal}"
        exit 1
    fi

    if [ ! -s "$KEY_PATH" ]; then
        echo -e "${red}SSH key is empty: $KEY_PATH${normal}"
        exit 1
    fi

    # Set appropriate permissions
    chmod 600 "$KEY_PATH" 2>/dev/null || true
}

# Function to get VMs IPs from hypervisor
get_vms_ips() {
    echo -e "${violet}Getting IPs of VMs: ${VMS:-all} from hypervisor: ${HYPERVISOR_NAME:-any} (project: $PROJECT)...${normal}"

    local command_args=""

    # Build command arguments based on provided parameters
    [ -n "$HYPERVISOR_NAME" ] && command_args="$command_args -hv \"$HYPERVISOR_NAME\""
    [ -n "$VMS" ] && command_args="$command_args -vms \"$VMS\""
    [ -n "$PROJECT" ] && command_args="$command_args -p $PROJECT"

    # Add debug flag if enabled
    [ "$TS_DEBUG" = "true" ] && command_args="$command_args -debug"

    # Trim leading space from arguments
    command_args="$(echo "$command_args" | sed 's/^ //')"

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] Command: bash \"$openstack_utils/$get_vms_list_script\" $command_args"

    echo -e "[DEBUG] Command: bash \"$openstack_utils/$get_vms_list_script\" $command_args"

    # Execute the command and capture output
    VMS=$(bash "$openstack_utils/$get_vms_list_script" $command_args)
#     2>&1)
    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] VMS: $VMS"
    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] exit_code $?"

    echo -e "[DEBUG] VMS: $VMS"
    echo "command_args"
    echo "$command_args"
    exit 0
#    local exit_code=$?
#    if [ $exit_code -ne 0 ]; then
#        echo -e "${red}Failed to get VMs IPs (exit code: $exit_code)${normal}"
#        echo -e "${red}Error output: $VMS${normal}"
#        return 1
#    fi

    if echo "$VMS" | grep -q "ERROR"; then
        echo -e "${red}Error in VMs list script: $VMS${normal}"
        return 1
    fi

    if [ -z "$VMS" ]; then
        echo -e "${yellow}No VMs found matching the criteria${normal}"
        echo -e "${yellow}Hypervisor: ${HYPERVISOR_NAME:-any}, VMs: ${VMS:-any}, Project: $PROJECT${normal}"
        return 1
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] Retrieved VMS: $VMS"
    return 0
}

# Function to check host connectivity
check_host_connectivity() {
    local ip="$1"

    if ping -c 2 -W 1 "$ip" &> /dev/null; then
        echo -e "${green}Ping successful: $ip${normal}"
        return 0
    else
        echo -e "${red}Ping failed: $ip${normal}"
        return 1
    fi
}

# Function to check SSH connectivity
check_ssh_connectivity() {
    local ip="$1"

    local ssh_output
    ssh_output=$(ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$TS_SSH_TIMEOUT" \
        -o BatchMode=yes \
        -i "$KEY_PATH" \
        "$VM_USER@$ip" \
        "echo 'SSH_OK'" 2>&1 | grep 'SSH_OK')

#    echo "debug: ssh_output: $ssh_output"
    if [ "$ssh_output" = "SSH_OK" ]; then
        echo -e "${green}SSH connection successful: $ip${normal}"
        return 0
    else
        echo -e "${red}SSH connection failed: $ip - $ssh_output${normal}"
        return 1
    fi
}

# Function to execute command on VM
execute_on_vm() {
    local ip="$1"

    echo -e "${violet}Executing command on $ip...${normal}"
    echo -e "${yellow}Command: $COMMAND_STR${normal}"

    ssh -t -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$TS_SSH_TIMEOUT" \
        -i "$KEY_PATH" \
        "$VM_USER@$ip" \
        "$COMMAND_STR"

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo -e "${green}Command executed successfully on $ip${normal}"
    else
        echo -e "${red}Command failed on $ip (exit code: $exit_code)${normal}"
    fi

    return $exit_code
}

# Main function to run commands on VMs
batch_run_commands() {
    local at_least_one_failure=false

    # Remove known_hosts to avoid conflicts
    [ -f "$HOME/.ssh/known_hosts" ] && rm -f "$HOME/.ssh/known_hosts"

    # Ask for confirmation if not in auto mode
    if [ "$DONT_ASK" != "true" ]; then
        read -p "Press Enter to continue or Ctrl+C to cancel..."
    fi

    # Get VMs IPs if not provided
#    if [ -z "$VMS" ] && [ -n "$HYPERVISOR_NAME" ]; then
    get_vms_ips
#    elif [ -z "$VMS" ]; then
#        get_vms_ips
#        echo -e "${red}No target specified. Use -hv or -ips option.${normal}"
#        exit 1
#    fi

    local exit_code=$?
    [ "$TS_DEBUG" = "true" ] && echo -e "exit_code from get_vms_ips: $exit_code"
    if [ $exit_code -ne 0 ]; then
        echo -e "${yellow}Warning: Failed to get the list of IPs${normal}"
        return 1
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG] Configuration:
      VMS: $VMS
      KEY_PATH: $KEY_PATH
      VM_USER: $VM_USER
      TS_SSH_TIMEOUT: $TS_SSH_TIMEOUT
    "

    if [ "$TS_DEBUG" = "true" ]; then
        echo -e "${yellow}[Warning] Debug mode enabled - skipping command execution${normal}"
        return 0
    fi

    # Process each VM
    for vm_tripl in $VMS; do

        vm_name=$(echo "$vm_tripl" | awk -F':' '{print $1}')
        vm_status=$(echo "$vm_tripl" | awk -F':' '{print $2}')
        vm_ip=$(echo "$vm_tripl" | awk -F':' '{print $3}')

        echo -e "
    [DEBUG] Configuration:
      vm_name: $vm_name
      vm_status: $vm_status
      vm_ip: $vm_ip
      "

        echo -e "${cyan}Processing VM: $vm_name VM status: $vm_status VM ip: $vm_ip${normal}"

        # Check ping connectivity
        if ! check_host_connectivity "$vm_ip"; then
            at_least_one_failure=true
            continue
        fi

        # Skip further checks if only ping is requested
        if [ "$ONLY_PING" = "true" ]; then
            continue
        fi

        # Check SSH connectivity
        if ! check_ssh_connectivity "$vm_ip"; then
            at_least_one_failure=true
            continue
        fi

        # Execute command if not only checking
        if [ "$ONLY_CHECK" = "false" ]; then
            if ! execute_on_vm "$vm_ip"; then
                at_least_one_failure=true
            fi
        fi

        sleep 1
    done

    # Set global variable for exit status
    if [ "$at_least_one_failure" = true ]; then
        return 1
    else
        return 0
    fi
}

# Main execution
main() {
    echo "Starting $script_name script..."

    parse_arguments "$@"
    validate_ssh_key
    batch_run_commands

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${yellow}Warning: Some operations failed${normal}"
    else
        echo -e "${green}All operations completed successfully${normal}"
    fi

    exit $exit_code
}

# Run main function
main "$@"