#!/bin/bash

# Script to execute commands on VMs via SSH
# Supports execution on all VMs of a hypervisor or specific VMs by IP/name
# return string like vms_name:status:ip(pub_net)

# Example manual command:
# ssh -o ProxyCommand="ssh -i $STAND_DIR_ENV/id_rsa -W %h:%p ebochkov-installer-v2-lcm-01.vm.lab.itkey.com"     -i /root/test_scripts_keystack/key_test.pem     cirros@10.224.135.37

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 14)

# Script configuration
script_name=$(basename "$0")
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
openstack_utils="$utils_dir/openstack"
default_ssh_timeout=15
get_vms_list_script="get_vms_list.sh"

# Default values
[[ -z $KEY_PATH ]] && KEY_PATH="$script_dir/key_test.pem"
[[ -z $OPENRC_PATH ]] && OPENRC_PATH="$HOME/openrc"
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME=""
[[ -z $ONLY_PING ]] && ONLY_PING=false
[[ -z $ONLY_CHECK ]] && ONLY_CHECK=false
[[ -z $VM_USER ]] && VM_USER="ubuntu"
[[ -z $COMMAND_STR ]] && COMMAND_STR="ls -la"
[[ -z $PROJECT ]] && PROJECT=""
[[ -z $DONT_ASK ]] && DONT_ASK="true"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $SSH_BY_PASS ]] && SSH_BY_PASS="false"
[[ -z $VMS ]] && VMS=""
[[ -z $TS_SSH_TIMEOUT ]] && TS_SSH_TIMEOUT="$default_ssh_timeout"
[[ -z $JUMP_HOST ]] && JUMP_HOST=""
[[ -z $JUMP_HOST_USER ]] && JUMP_HOST_USER="$(whoami)"
[[ -z $JUMP_HOST_KEY ]] && JUMP_HOST_KEY="${STAND_DIR_ENV:+$STAND_DIR_ENV/id_rsa}"
[[ -z $PING_TIMEOUT ]] && PING_TIMEOUT="3"

# Function to display help information
show_help() {
    echo -e "
    Usage: $0 [OPTIONS]

    Execute commands on VMs via SSH. Can target all VMs on a hypervisor or specific VMs by IP.

    Options:
      -hv <name>              Hypervisor name
      -u, -user <username>    SSH user (default: ubuntu)
      -c, -command <command>  Command to execute on VMs
      -k, -key <path>         SSH private key file path
      -jh, -jump-host <host>       Jump host (bastion) IP or FQDN to hop through via SSH ProxyCommand
      -jhu, -jump-host-user <u>    User for the jump host login (default: current user, \$(whoami))
      -jhk, -jump-host-key <path>  SSH private key for the jump host login
                                   (default: \$STAND_DIR_ENV/id_rsa, if STAND_DIR_ENV is set)
      -pt, -ping-timeout <s>  Ping timeout in seconds (default: 3). Ping is advisory only:
                              a failed ping never blocks the following SSH check/exec.
      -ping                   Only perform ping check
      -p, -project <name>     OpenStack project name (default: admin)
      -dont_ask               Perform actions automatically without confirmation
      -vms                    Space-separated list of IP or name
      -v, -debug              Enable debug output
      -check                  Only check SSH access without executing commands
      -t, -timeout <seconds>  SSH connection timeout (default: 15; consider raising further
                              when using -jh, since the jump adds an extra connection hop)
      -ssh_by_pass            Enable ssh by password
      --help                  Show this help message

    Examples:
      # Run command on all VMs of a hypervisor
      $0 -hv compute-01 -c 'df -h'

      # Check connectivity to specific VMs
      $0 -vms \"192.168.1.10 192.168.1.11\" -check
      $0 -vms \"vm_name1 vm_name2\" -check

      # Only ping check
      $0 -hv compute-01 -ping

      # Run command through a jump host (bastion), since target network
      # is not reachable directly from this machine.
      # Jump host login (root@bastion, separate key) differs from target login (cirros@vm, target key)
      $0 -vms \"10.224.135.37\" -jh bastion.example.com -jhu root -jhk /root/.ssh/id_rsa -u cirros -c 'uptime'
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
                echo "SSH user: $VM_USER"
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
            -jh|-jump-host)
                JUMP_HOST="$2"
                echo "Using jump host: $JUMP_HOST"
                shift 2
                ;;
            -jhu|-jump-host-user)
                JUMP_HOST_USER="$2"
                echo "Jump host user: $JUMP_HOST_USER"
                shift 2
                ;;
            -jhk|-jump-host-key)
                JUMP_HOST_KEY="$2"
                echo "Jump host key: $JUMP_HOST_KEY"
                shift 2
                ;;
            -pt|-ping-timeout)
                PING_TIMEOUT="$2"
                echo "Ping timeout: $PING_TIMEOUT seconds"
                shift 2
                ;;
            -ssh_by_pass)
                SSH_BY_PASS="true"
                echo "Enable SSH by password: SSH_BY_PASS: $SSH_BY_PASS"
                shift
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

# Function to validate jump host SSH key (only relevant when -jh is used)
validate_jump_host_key() {
    if [ -z "$JUMP_HOST_KEY" ]; then
        echo -e "${red}Jump host is set but no jump host key is configured (use -jhk or set STAND_DIR_ENV)${normal}"
        exit 1
    fi

    if [ ! -f "$JUMP_HOST_KEY" ]; then
        echo -e "${red}Jump host SSH key not found: $JUMP_HOST_KEY${normal}"
        exit 1
    fi

    if [ ! -s "$JUMP_HOST_KEY" ]; then
        echo -e "${red}Jump host SSH key is empty: $JUMP_HOST_KEY${normal}"
        exit 1
    fi

    chmod 600 "$JUMP_HOST_KEY" 2>/dev/null || true
}

# Function to get VMs IPs from hypervisor
get_vms_ips() {
    echo -e "${blue}Getting IPs of VMs: ${VMS:-all} from hypervisor: ${HYPERVISOR_NAME:-any} (project: $PROJECT)...${normal}"

    local command_args=""

    command_args=()

    [ -n "$HYPERVISOR_NAME" ] && command_args+=(-hv "$HYPERVISOR_NAME")
    [ -n "$VMS" ] && command_args+=(-vms "$VMS")
    [ -n "$PROJECT" ] && command_args+=(-p "$PROJECT")

    VMS=$(bash "$openstack_utils/$get_vms_list_script" "${command_args[@]}")

    echo -e "VMS:
    $VMS"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${red}Failed to get VMs IPs (exit code: $exit_code)${normal}"
        echo -e "${red}Error output: $VMS${normal}"
        return 1
    fi

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
# NOTE: this check is ADVISORY ONLY - it never blocks the following SSH
# check/exec steps. A failed ping (e.g. due to missing raw-socket
# permissions on the jump host, or a target that just drops ICMP) does
# not necessarily mean the host is unreachable over SSH/TCP.
# If a jump host is set, ping is executed FROM the jump host, since the
# target network may not be reachable directly from this machine.
check_vm_connectivity() {
    local ip="$1"

    if [ -n "$JUMP_HOST" ]; then
        [ "$TS_DEBUG" = "true" ] && echo "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=\"$TS_SSH_TIMEOUT\" -i \"$JUMP_HOST_KEY\" \"$JUMP_HOST_USER@$JUMP_HOST\" \"ping -c 2 -W $PING_TIMEOUT $ip\""
        if ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout="$TS_SSH_TIMEOUT" \
            -i "$JUMP_HOST_KEY" \
            "$JUMP_HOST_USER@$JUMP_HOST" \
            "ping -c 2 -W $PING_TIMEOUT $ip" &> /dev/null; then
            echo -e "${green}Ping successful: $ip${normal}"
            return 0
        else
            echo -e "${yellow}Ping failed: $ip${normal}"
            return 1
        fi
    fi

    if ping -c 2 -W "$PING_TIMEOUT" "$ip" &> /dev/null; then
        echo -e "${green}Ping successful: $ip${normal}"
        return 0
    else
        echo -e "${yellow}Ping failed: $ip${normal}"
        return 1
    fi
}

# Function to check SSH connectivity
check_ssh_connectivity() {
    local ip="$1"
    local ssh_output
    local exit_code
    local jump_opts=()

    if [ -n "$JUMP_HOST" ]; then
        jump_opts=(-o "ProxyCommand=ssh -i $JUMP_HOST_KEY -W %h:%p $JUMP_HOST_USER@$JUMP_HOST")
    fi

    [ "$TS_DEBUG" = "true" ] && {
    echo "ssh_output=\$(ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=\"$TS_SSH_TIMEOUT\" \
        -o BatchMode=yes \
        ${jump_opts[*]} \
        -i \"$KEY_PATH\" \
        \"$VM_USER@$ip\" \
        \"echo \'SSH_OK\'\" 2>&1)";}

    ssh_output=$(ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$TS_SSH_TIMEOUT" \
        -o BatchMode=yes \
        "${jump_opts[@]}" \
        -i "$KEY_PATH" \
        "$VM_USER@$ip" \
        "echo 'SSH_OK'" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ] && echo "$ssh_output" | grep -q '^SSH_OK$'; then
        echo -e "${green}SSH connection successful: $ip${normal}"
        return 0
    else
        echo -e "${red}SSH connection failed: $ip - exit code: $exit_code, error: $ssh_output${normal}"
        return 1
    fi
}

# Function to execute command on VM
execute_on_vm() {
    local ip="$1"
    local jump_opts=()

    if [ -n "$JUMP_HOST" ]; then
        jump_opts=(-o "ProxyCommand=ssh -i $JUMP_HOST_KEY -W %h:%p $JUMP_HOST_USER@$JUMP_HOST")
    fi

    echo -e "${blue}Executing command on $ip$( [ -n "$JUMP_HOST" ] && echo " (via jump host $JUMP_HOST)" )...${normal}"
    echo -e "${yellow}Command: $COMMAND_STR${normal}"

    [ "$TS_DEBUG" = "true" ] && {
    echo "ssh -t -o StrictHostKeyChecking=no \
               -o ConnectTimeout=\"$TS_SSH_TIMEOUT\" \
               ${jump_opts[*]} \
               $KEY_STRING \
               \"$VM_USER@$ip\" \
               \"$COMMAND_STR\"";}

    ssh -t -o StrictHostKeyChecking=no \
    -o ConnectTimeout="$TS_SSH_TIMEOUT" \
    "${jump_opts[@]}" \
    $KEY_STRING \
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
    local success_count=0
    local failure_count=0
    local ping_failed_count=0
    local total_vms=0

    local mode_desc="command execution"
    [ "$ONLY_PING" = "true" ] && mode_desc="ping check only"
    [ "$ONLY_PING" != "true" ] && [ "$ONLY_CHECK" = "true" ] && mode_desc="SSH access check only"
    echo -e "${blue}Mode: $mode_desc${normal}"
    [ "$ONLY_PING" != "true" ] && [ "$ONLY_CHECK" = "false" ] && echo -e "${blue}Command to run on each VM: '$COMMAND_STR'${normal}"
    # Remove known_hosts to avoid conflicts
    [ -f "$HOME/.ssh/known_hosts" ] && rm -f "$HOME/.ssh/known_hosts"

    # Ask for confirmation if not in auto mode
    if [ "$DONT_ASK" != "true" ]; then
        read -p "Press Enter to continue or Ctrl+C to cancel..."
    fi

    # Get VMs IPs
    get_vms_ips
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo -e "${yellow}Warning: Failed to get the list of IPs${normal}"
        return 1
    fi

    # Process each VM
    for vm_tripl in $VMS; do
        ((total_vms++))
        local current_vm_failed=false

        vm_name=$(echo "$vm_tripl" | awk -F':' '{print $1}')
        vm_status=$(echo "$vm_tripl" | awk -F':' '{print $2}')
        vm_ip=$(echo "$vm_tripl" | awk -F':' '{print $3}')

        echo -e "${cyan}Processing VM: $vm_name | Status: $vm_status | IP: $vm_ip${normal}"

        # 1. Check ping connectivity (advisory only - does NOT block next steps,
        #    it's just tracked/reported separately, e.g. useful when ping via
        #    jump host is unreliable due to raw-socket permissions)
        if ! check_vm_connectivity "$vm_ip"; then
            ((ping_failed_count++))
            if [ "$ONLY_PING" = "true" ]; then
                current_vm_failed=true
            fi
        fi

        # 2. Check SSH connectivity (if not bypassed) - runs regardless of ping result
        if [ "$ONLY_PING" != "true" ] && [ "$SSH_BY_PASS" != "true" ] && [ "$current_vm_failed" = false ]; then
            if ! check_ssh_connectivity "$vm_ip"; then
                current_vm_failed=true
            fi
        fi

        # 3. Execute command (if not only checking and no failures so far)
        if [ "$ONLY_PING" != "true" ] && [ "$ONLY_CHECK" = "false" ] && [ "$current_vm_failed" = false ]; then
            if ! execute_on_vm "$vm_ip"; then
                current_vm_failed=true
            fi
        fi

        # Update counters
        if [ "$current_vm_failed" = true ]; then
            ((failure_count++))
            at_least_one_failure=true
        else
            ((success_count++))
        fi

        sleep 1
    done

    # --- Summary Report ---
    echo -e "\n${cyan}=======================================${normal}"
    echo -e "Execution Summary:"
    echo -e "  Total VMs processed: $total_vms"
    echo -e "  ${green}Successful:         $success_count${normal}"
    echo -e "  ${red}Failed:             $failure_count${normal}"
    echo -e "  ${yellow}Ping failed (info): $ping_failed_count${normal}"
    echo -e "${cyan}=======================================${normal}\n"

    # Set return status
    [ "$at_least_one_failure" = true ] && return 1 || return 0
}

# Main execution
main() {
    echo "Starting $script_name script..."

    parse_arguments "$@"
    if [ "$SSH_BY_PASS" != "true" ]; then
        KEY_STRING="-i $KEY_PATH"
        validate_ssh_key
    fi

    if [ -n "$JUMP_HOST" ]; then
        validate_jump_host_key
    fi

    echo "VM_USER: $VM_USER"
    echo "KEY_STRING: $KEY_STRING"
    if [ -n "$JUMP_HOST" ]; then
        echo "JUMP_HOST: $JUMP_HOST"
        echo "JUMP_HOST_USER: $JUMP_HOST_USER"
        echo "JUMP_HOST_KEY: $JUMP_HOST_KEY"
    fi

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