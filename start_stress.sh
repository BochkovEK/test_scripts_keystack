#!/bin/bash

normal=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
blue=$(tput setaf 6)
violet=$(tput setaf 5)

script_dir=$(dirname "$0")
utils_dir="$script_dir/utils"
openstack_utils="$utils_dir/openstack"
get_active_vms_list_script="get_vms_list.sh"
check_ssh_connectivity_script="check_ssh_connectivity.sh"

external_scripts=(
    "$utils_dir/$check_ssh_connectivity_script"
)

OPENRC_PATH="${OPENRC_PATH:-$HOME/openrc}"
KEY_PATH="${KEY_PATH:-$script_dir/key_test.pem}"
HYPERVISOR_NAME="${HYPERVISOR_NAME:-}"
CPUS="${CPUS:-2}"
RAM="${RAM:-4}"
TIME_OUT="${TIME_OUT:-}"
TYPE_TEST="${TYPE_TEST:-cpu}"
PROJECT="${PROJECT:-}"
VM_USER="${VM_USER:-ubuntu}"
TS_DEBUG="${TS_DEBUG:-false}"
UNITS="${UNITS:-G}"
VMS_LIST_FILE="${VMS_LIST_FILE:-}"
VMS="${VMS:-}"
MOUNT_TO_RAM="${MOUNT_TO_RAM:-false}"

show_help() {
    echo -E "
    CPU/RAM Stress Test for OpenStack VMs

    Usage: $0 [OPTIONS]

    Options:
      -hv <name>              Hypervisor name
      -cpu <number>           Number of CPUs for stress test
      -ram <gb>               GB of RAM for stress test
      -units <unit>           Units for RAM stress: B, K, M, G
      -mor, -mount_to_ram     Use tmpfs mount for RAM test
      -t, -time_out <sec>     Timeout for stress test in seconds
      -key <path>             Path to SSH key file
      -p, -project <name>     OpenStack project name
      -u, -vm_user <name>     VM SSH username
      -v, -debug              Enable debug output
      -vms_list_file <path>    Path to file with VM IP list
      -vms <list>             Space-separated list of VM IPs
      --help                  Show this help message

    Example:
      $0 -cpu 2 -hv compute-01 -p myproject -t 300
    "
}

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
            -vms_list_file)
                if [ -z "$VMS" ]; then
                    VMS_LIST_FILE="$2"
                    echo "Using VM list file: $VMS_LIST_FILE"
                    if [ -f "$VMS_LIST_FILE" ]; then
                        VMS=$(cat "$VMS_LIST_FILE" | tr '\n' ' ' | sed 's/ $//')
                        echo "Loaded VMs from file: $VMS"
                    else
                        echo -e "${red}VM list file not found: $VMS_LIST_FILE${normal}"
                        exit 1
                    fi
                else
                    echo "Warning: -vms_list_file ignored because -vms is already specified"
                fi
                shift 2
                ;;
            -vms)
                VMS="$2"
                echo "Using IP list: $VMS"
                shift 2
                ;;
            -mor|-mount_to_ram)
                MOUNT_TO_RAM="true"
                echo "Using tmpfs mount for RAM test"
                shift
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

extract_ip_from_vms_list() {
    local VM_LIST="$1"
    local vms=""

    while IFS= read -r line; do
        if [[ "$line" == *:*:* ]]; then
            local ip="${line##*:}"
            vms="$vms $ip"
        else
            vms="$vms $line"
        fi
    done <<< "$VM_LIST"

    echo "$vms" | tr -s ' ' | sed 's/^ //'
}

get_vms_ips() {
    local hv_info=""

    if [ -n "$VMS" ]; then
        hv_info="specific VMs: $VMS"

        [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] Getting VMs from: $hv_info"

        local command_args="-vms \"$VMS\""
        [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] Command args for VM list: $command_args"

#        local VM_LIST
        VM_LIST=$(eval "bash \"$openstack_utils/$get_active_vms_list_script\" $command_args")

        if echo "$VM_LIST" | grep -q "ERROR"; then
            echo -e "${red}Failed to get VMs list${normal}"
            exit 1
        fi

        VMs_IPs=$(extract_ip_from_vms_list "$VM_LIST")
    else
        hv_info="VMs"
        [ -n "$HYPERVISOR_NAME" ] && hv_info="$hv_info on hypervisor: $HYPERVISOR_NAME"
        [ -n "$PROJECT" ] && hv_info="$hv_info in project: $PROJECT"
        [ -z "$HYPERVISOR_NAME" ] && [ -z "$PROJECT" ] && hv_info="all VMs"

        [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] Getting VMs from: $hv_info"

        local command_args=""
        [ -n "$HYPERVISOR_NAME" ] && command_args="$command_args -hv \"$HYPERVISOR_NAME\""
        [ -n "$PROJECT" ] && command_args="$command_args -p \"$PROJECT\""

        [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] Command args for VM list: $command_args"

#        local VM_LIST
        VM_LIST=$(eval "bash \"$openstack_utils/$get_active_vms_list_script\" $command_args")

        if echo "$VM_LIST" | grep -q "ERROR"; then
            echo -e "${red}Failed to get VMs list${normal}"
            exit 1
        fi

        VMs_IPs=$(extract_ip_from_vms_list "$VM_LIST")
    fi

    if [ -z "$VMs_IPs" ]; then
        echo -e "${red}No VMs found for stress testing${normal}"
        exit 1
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] VMs_IPs: $VMs_IPs"
    echo "$hv_info"
}

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
        timeout_help_string="Timeout: $TIME_OUT seconds"
        stress_args="$stress_args -t $TIME_OUT"
    else
        timeout_help_string="No timeout (run until stopped)"
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG] stress_args: $stress_args"
}

copy_and_run_stress() {
    local vm_ip="$1"

    echo "Processing VM: $vm_ip"

    if [ "$TYPE_TEST" = "ram" ] && [ "$MOUNT_TO_RAM" = "true" ]; then
        echo "Starting ${yellow}'Mount to RAM'${normal} type ram load on $vm_ip using tmpfs..."
        # !!! Units only GB or MB
        if [ "$UNITS" = "G" ]; then
            RAM_SIZE=$(($RAM * 1024))
        else
            RAM_SIZE=$RAM
        fi

        ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$VM_USER@$vm_ip" \
            "sudo mkdir -p /mnt/ram && sudo mount -t tmpfs -o size=${RAM_SIZE}M tmpfs /mnt/ram"

        ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$VM_USER@$vm_ip" \
            "sudo dd if=/dev/urandom of=/mnt/ram/bigfile bs=1M count=${RAM_SIZE} status=progress"

        echo -e "${green}\nRAM load started on $vm_ip using tmpfs${normal}"
        return 0
    fi

    echo "Copying stress tool to $vm_ip..."
    [ "$TS_DEBUG" = "true" ] && echo -e "[DEBUG]
    command: scp -o StrictHostKeyChecking=no -i \"$KEY_PATH\" \"$script_dir/stress\" \"$VM_USER@$vm_ip:~/\" >/dev/null 2>&1
    "
    if ! scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "$script_dir/stress" "$VM_USER@$vm_ip:~/" >/dev/null 2>&1; then
        echo -e "${red}Failed to copy stress tool to $vm_ip${normal}"
        return 1
    fi

    ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$VM_USER@$vm_ip" "chmod +x ~/stress" >/dev/null 2>&1

    echo "Starting $TYPE_TEST stress on $vm_ip..."
    local ssh_command="nohup ./stress $stress_args > /dev/null 2>&1 &"

    if ! ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$VM_USER@$vm_ip" "$ssh_command"; then
        echo -e "${red}Failed to start stress on $vm_ip${normal}"
        return 1
    fi

    echo -e "${green}Stress test started on $vm_ip${normal}"
    return 0
}

check_vm_connectivity() {
    echo "Checking VM connectivity..."

    local all_connected=true

    for ip in $VMs_IPs; do
        echo -e "${blue}Testing VM: $ip${normal}"

        if test_ssh_connection "stress-test-vm" "$ip" "10" "$VM_USER"; then
            echo -e "${green}✓ SSH access to $ip - OK${normal}"
        else
            echo -e "${red}✗ SSH access failed to $ip${normal}"
            all_connected=false
        fi
        echo ""
    done

    return $([ "$all_connected" = true ])
}

batch_run_stress() {
    echo "Starting stress..."

    read -p "Press Enter to continue or Ctrl+C to cancel: "

    local success_count=0
    local total_count=0

    for ip in $VMs_IPs; do
        ((total_count++))
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

validate_environment() {
    if [ ! -f "$script_dir/stress" ]; then
        echo -e "${red}Stress binary not found: $script_dir/stress${normal}"
        exit 1
    fi

    if [ ! -f "$KEY_PATH" ]; then
        echo -e "${red}SSH key not found: $KEY_PATH${normal}"
        exit 1
    fi

    if [ "$TYPE_TEST" = "cpu" ] && [ "$CPUS" -le 0 ]; then
        echo -e "${red}Invalid CPU count: $CPUS${normal}"
        exit 1
    fi

    if [ "$TYPE_TEST" = "ram" ] && [ "$RAM" -le 0 ]; then
        echo -e "${red}Invalid RAM size: $RAM${normal}"
        exit 1
    fi
}

check_configuration() {
    echo -e "
${violet}Stress Test Configuration:${normal}
    SSH Key:              $KEY_PATH
    VM User:              $VM_USER
    Test Type:            $TYPE_TEST
    Mount to RAM:         $MOUNT_TO_RAM
    load_string:          $load_string
    timeout_help_string:  $timeout_help_string
    Debug Mode:           $TS_DEBUG
    VMS:                  $VM_LIST
    "

    read -p "Press Enter to continue or Ctrl+C to cancel: "
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

main() {
    parse_arguments "$@"
    validate_environment

    rm -f /root/.ssh/known_hosts 2>/dev/null

    get_vms_ips

    get_mode_strings

    check_configuration

    if ! check_vm_connectivity; then
        echo -e "${red}VM connectivity check failed${normal}"
        exit 1
    fi

    batch_run_stress

    echo -e "${green}Stress test initialization completed successfully!${normal}"
}

main "$@"