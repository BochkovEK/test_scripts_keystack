#!/bin/bash

# CPU/RAM stress test script for OpenStack VMs
# Supports stress testing on all VMs of a hypervisor or specific VMs

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)

# Script paths
script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
openstack_utils="$utils_dir/openstack"
get_active_vms_ips_list_script="get_vms_list.sh"
#check_vm_script="command_on_vms.sh"
#check_openrc_script="check_openrc.sh"
#check_openstack_cli_script="check_openstack_cli.sh"

# Default values
OPENRC_PATH="${OPENRC_PATH:-$HOME/openrc}"
KEY_PATH="${KEY_PATH:-$script_dir/key_test.pem}"
HYPERVISOR_NAME="${HYPERVISOR_NAME:-}"
CPUS="${CPUS:-2}"
RAM="${RAM:-4}"
TIME_OUT="${TIME_OUT:-}"
TYPE_TEST="${TYPE_TEST:-cpu}"
PROJECT="${PROJECT:-admin}"
VM_USER="${VM_USER:-ubuntu}"
TS_DEBUG="${TS_DEBUG:-false}"
UNITS="${UNITS:-G}"
IP_LIST_FILE="${IP_LIST_FILE:-}"
VMs_IPs="${VMs_IPs:-}"

# Function to display help information
show_help() {
    echo -E "
    CPU/RAM Stress Test for OpenStack VMs

    Usage: $0 [OPTIONS]

    Options:
      -hv <name>              Hypervisor name (!!! not ip)
      -cpu <number>           Number of CPUs for stress test
      -ram <gb>               GB of RAM for stress test
      -units <unit>           Units for RAM stress: B, K, M, G (default: G)
      -t, -time_out <sec>     Timeout for stress test in seconds
      -key <path>             Path to SSH key file
      -p, -project <name>     OpenStack project name
      -u, -vm_user <name>     VM SSH username
      -v, -debug              Enable debug output
      -ip_list_file <path>    Path to file with VM IP list
      -ips <list>             Space-separated list of VM IPs
      --help                  Show this help message

    Example:
      $0 -cpu 2 -hv compute-01 -p myproject -t 300
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
            -cpu)
                CPUS="$2"
                TYPE_TEST="cpu"
                echo "CPU stress with $CPUS cores"
                shift 2
                ;;
            -ram)
                RAM="$2"
                TYPE_TEST="ram"
                echo "RAM stress with $RAM GB"
                shift 2
                ;;
            -units)
                UNITS="$2"
                echo "Using units: $UNITS"
                shift 2
                ;;
            -key)
                KEY_PATH="$2"
                echo "Using SSH key: $KEY_PATH"
                shift 2
                ;;
            -p|-project)
                PROJECT="$2"
                echo "Using project: $PROJECT"
                shift 2
                ;;
            -u|-vm_user)
                VM_USER="$2"
                echo "Using VM user: $VM_USER"
                shift 2
                ;;
            -t|-time_out)
                TIME_OUT="$2"
                echo "Timeout: $TIME_OUT seconds"
                shift 2
                ;;
            -v|-debug)
                TS_DEBUG="true"
                echo "Debug mode enabled"
                shift
                ;;
            -ip_list_file)
                IP_LIST_FILE="$2"
                echo "Using IP list file: $IP_LIST_FILE"
                shift 2
                ;;
            -ips)
                VMs_IPs="$2"
                echo "Using IP list: $VMs_IPs"
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

# Function to extract IPs from vm_name:status:ip format
extract_ips_from_vm_list() {
    local vm_list="$1"
    local ips=""

    while IFS= read -r line; do
        if [[ "$line" == *:*:* ]]; then
            local ip="${line##*:}"
            ips="$ips $ip"
        else
            # If not in expected format, assume it's already an IP
            ips="$ips $line"
        fi
    done <<< "$vm_list"

    echo "$ips" | tr -s ' ' | sed 's/^ //'
}

# Function to get VMs IPs
get_vms_ips() {
    local hv_info=""

    if [ -z "$VMs_IPs" ]; then
        if [ -z "$IP_LIST_FILE" ]; then
            if [ -z "$HYPERVISOR_NAME" ]; then
                hv_info="all VMs in project: $PROJECT"
            else
                hv_info="VMs on hypervisor: $HYPERVISOR_NAME"
            fi

            [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] Getting VMs from: $hv_info"

            # Get VMs list in format: vm_name:status:ip
            export HYPERVISOR_NAME="$HYPERVISOR_NAME"
            export PROJECT="$PROJECT"

            local vm_list
            vm_list=$(bash "$openstack_utils/$get_active_vms_ips_list_script")

            if echo "$vm_list" | grep -q "ERROR"; then
                echo -e "${red}Failed to get VMs list${normal}"
                exit 1
            fi

            # Extract IPs from the formatted output
            VMs_IPs=$(extract_ips_from_vm_list "$vm_list")
#            [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] VMs_IPs: $VMs_IPs"
        else
            # Read IPs from file
            if [ ! -f "$IP_LIST_FILE" ]; then
                echo -e "${red}IP list file not found: $IP_LIST_FILE${normal}"
                exit 1
            fi
            VMs_IPs=$(cat "$IP_LIST_FILE")
            hv_info="VMs from file: $IP_LIST_FILE"
        fi
    else
        hv_info="Manual IP list provided"
    fi

    # Validate we have IPs
    if [ -z "$VMs_IPs" ]; then
        echo -e "${red}No VMs found for stress testing${normal}"
        exit 1
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] VMs_IPs: $VMs_IPs"
    echo "$hv_info"
}

# Function to get mode and timeout strings
get_mode_strings() {
    if [ "$TYPE_TEST" = "cpu" ]; then
        load_string="CPU:            $CPUS cores"
        stress_args="-c $CPUS"
    elif [ "$TYPE_TEST" = "ram" ]; then
        load_string="RAM:            $RAM $UNITS"
        stress_args="--vm 1 --vm-bytes ${RAM}${UNITS}"
    else
        echo -e "${red}Unsupported test type: $TYPE_TEST${normal}"
        exit 1
    fi

    if [ -n "$TIME_OUT" ]; then
        time_out_help_string="Timeout: $TIME_OUT seconds"
        stress_args="$stress_args -t $TIME_OUT"
    else
        time_out_help_string="No timeout (run until stopped)"
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] stress_args: $stress_args"
}

# Function to copy and run stress tool
copy_and_run_stress() {
    local vm_ip="$1"

    echo "Processing VM: $vm_ip"

#    # Check connectivity
#    if ! ping -c 2 "$vm_ip" &> /dev/null; then
#        echo -e "${red}No connectivity to $vm_ip${normal}"
#        return 1
#    fi

    # Copy stress binary
    echo "Copying stress tool to $vm_ip..."
    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]
    command: scp -o StrictHostKeyChecking=no -i \"$KEY_PATH\" \"$script_dir/stress\" \"$VM_USER@$vm_ip:~/\" >/dev/null 2>&1
    "
    if ! scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "$script_dir/stress" "$VM_USER@$vm_ip:~/" >/dev/null 2>&1; then
        echo -e "${red}Failed to copy stress tool to $vm_ip${normal}"
        return 1
    fi

    # Set executable permission
    ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$VM_USER@$vm_ip" "chmod +x ~/stress" >/dev/null 2>&1

    # Run stress test
    echo "Starting $TYPE_TEST stress on $vm_ip..."
    local ssh_command="nohup ./stress $stress_args > /dev/null 2>&1 &"

    if ! ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$VM_USER@$vm_ip" "$ssh_command"; then
        echo -e "${red}Failed to start stress on $vm_ip${normal}"
        return 1
    fi

    echo -e "${green}Stress test started on $vm_ip${normal}"
    return 0
}

# Function to check VM connectivity
check_vm_connectivity() {
    echo "Checking VM connectivity..."

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] VMs_IPs: $VMs_IPs"
    for ip in $VMs_IPs; do
        if ping -c 2 "$ip" &> /dev/null; then
            echo -e "${green}✓ Connectivty to $ip - OK${normal}"
        else
            echo -e "${red}✗ No connectivity to $ip${normal}"
#            return 0
        fi

        # Check SSH access
        if ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" -o ConnectTimeout=5 "$VM_USER@$ip" "echo SSH_OK" >/dev/null 2>&1; then
            echo -e "${green}✓ SSH access to $ip - OK${normal}"
        else
            echo -e "${red}✗ SSH access failed to $ip${normal}"
            return 1
        fi
    done

    return 0
}

# Function to batch run stress tests
batch_run_stress() {
#    local hv_info="$1"
    echo "Starting stress..."

    read -p "Press Enter to continue or Ctrl+C to cancel..."

    local success_count=0
    local total_count=0

    for ip in $VMs_IPs; do
        ((total_count++))
#        copy_and_run_stress "$ip"
        if copy_and_run_stress "$ip"; then
            ((success_count++))
        fi
        echo ""
    done

    echo -e "${green}Stress tests completed: $success_count/$total_count VMs successful${normal}"

    if [ $success_count -eq 0 ]; then
        echo -e "${red}No stress tests were successfully started${normal}"
        exit 1
    fi
}

# Function to validate environment
validate_environment() {
    # Check if stress binary exists
    if [ ! -f "$script_dir/stress" ]; then
        echo -e "${red}Stress binary not found: $script_dir/stress${normal}"
        exit 1
    fi

    # Check if SSH key exists
    if [ ! -f "$KEY_PATH" ]; then
        echo -e "${red}SSH key not found: $KEY_PATH${normal}"
        exit 1
    fi

    # Validate test parameters
    if [ "$TYPE_TEST" = "cpu" ] && [ "$CPUS" -le 0 ]; then
        echo -e "${red}Invalid CPU count: $CPUS${normal}"
        exit 1
    fi

    if [ "$TYPE_TEST" = "ram" ] && [ "$RAM" -le 0 ]; then
        echo -e "${red}Invalid RAM size: $RAM${normal}"
        exit 1
    fi
}

check_configuration () {
      echo -e "
${violet}Stress Test Configuration:${normal}
    SSH Key:          $KEY_PATH
    VM User:          $VM_USER
    Test Type:        $TYPE_TEST
    VMs_IPs:          $VMs_IPs
    $load_string
    $time_out_help_string
    Debug Mode:       $TS_DEBUG
    "
#    Target:           $hv_info

    read -p "Press Enter to continue or Ctrl+C to cancel..."
}

# Main execution function
main() {
    parse_arguments "$@"
    validate_environment

    # Remove known hosts to avoid conflicts
    rm -f /root/.ssh/known_hosts 2>/dev/null

    # Get VMs IPs
#    local hv_info
#    hv_info=$(
    get_vms_ips

    # Get mode strings
    get_mode_strings

    check_configuration

    # Check connectivity
    if ! check_vm_connectivity; then
        echo -e "${red}VM connectivity check failed${normal}"
        exit 1
    fi

    # Run stress tests
    batch_run_stress
#     "$hv_info"

    echo -e "${green}Stress test initialization completed successfully!${normal}"
}

# Run main function
main "$@"