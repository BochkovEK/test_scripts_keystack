#!/bin/bash

# Color definitions
normal=$(tput sgr0)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
green=$(tput setaf 2)
#blue=$(tput setaf 4)

# Default values
default_interface_name="eth0"
default_number_of_cycle=20
default_sleep_time=5

# Set parameters from environment or use defaults
[[ -z $TS_NUMBER_OF_CYCLES ]] && TS_NUMBER_OF_CYCLES=$default_number_of_cycle
[[ -z $TS_SLEEP_TIME ]] && TS_SLEEP_TIME=$default_sleep_time
[[ -z $TS_FLAPPING_INTERFACE_LOG_PATH ]] && TS_FLAPPING_INTERFACE_LOG_PATH=""


# Generate log file name with timestamp and initialize logging
setup_logging() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local log_path="${TS_FLAPPING_INTERFACE_LOG_PATH:-/tmp}"

    # Ensure directory exists
    mkdir -p "$log_path"

    LOG_FILE="${log_path}/flapping_interface_${timestamp}.log"
    echo "Logging output to: $LOG_FILE"

    # Export for potential use in other functions
    export LOG_FILE
}

# Check interface state (UP/DOWN/UNKNOWN)
check_interface_state() {
    local interface=$1
    local state

    state=$(ip -o link show $interface 2>/dev/null | sed -nE 's/.*\s(UP|DOWN|UNKNOWN)\s.*/\1/p')

    if [[ "$state" == "UP" ]]; then
        echo -e "${green}$interface: UP${normal}"
        return 0
    elif [[ "$state" == "DOWN" ]]; then
        echo -e "${red}$interface: DOWN${normal}"
        return 1
    else
        echo -e "${yellow}$interface: UNKNOWN (state: ${state:-N/A})${normal}"
        return 2
    fi
}

# Check all interfaces in array
check_all_interfaces() {
    local interfaces=("$@")
    local error_flag=0

    echo "---------------------"
    for interface in "${interfaces[@]}"; do
        check_interface_state "$interface"
        local state=$?

        if [ $state -eq 2 ]; then
            error_flag=1
        elif [ $state -eq 1 ]; then
            error_flag=1
        fi
    done
    echo "---------------------"

    if [ $error_flag -eq 1 ]; then
      echo -e "${yellow}[NOTICE] To try raiseup interface:
      ip link set <interface_name> up${normal}"
    fi
    return $error_flag
}

# Get all system interfaces
get_all_interfaces() {
    local interfaces_array=()

    mapfile -t interfaces_array < <(
        ip -o link show | awk -F': ' '{print $2}' |
        while IFS= read -r iface; do
            echo "${iface%%@*}"
        done
    )

    printf '%s\n' "${interfaces_array[@]}"
}

# Validate interface exists
validate_interface() {
    local interface_name="$1"
    local all_interfaces=("$2")
    local found=false

    for item in "${all_interfaces[@]}"; do
        if [[ "$item" == "$interface_name" ]]; then
            found=true
            break
        fi
    done

    if [ ! "$found" = true ]; then
        echo -e "${red}[ERROR]: Interface $interface_name does not exist!${normal}"
        echo "Available interfaces:"
        printf '%s\n' "${all_interfaces[@]}"
        return 1
    fi
    return 0
}

# Set interface name from arguments or environment
set_interface_name() {
    if [ -z "$1" ]; then
        if [ -z "$TS_INTERFACE_NAME" ]; then
            echo "Interface name can be defined either as argument or environment variable 'TS_INTERFACE_NAME'"
            TS_INTERFACE_NAME=$default_interface_name
            echo "Interface name is set by default: '$TS_INTERFACE_NAME'"
        else
            echo "Interface name is: '$TS_INTERFACE_NAME'"
        fi
    else
        TS_INTERFACE_NAME=$1
        echo "Interface name is: '$TS_INTERFACE_NAME'"
    fi

    # Remove @ suffix from interface name
    TS_INTERFACE_NAME=${TS_INTERFACE_NAME%%@*}
    echo "$TS_INTERFACE_NAME"
}

# Display test parameters
show_parameters() {
    echo -e "\nStart flapping with the following parameters?"
    echo "  TS_INTERFACE_NAME:          $TS_INTERFACE_NAME"
    echo "  TS_NUMBER_OF_CYCLES:        $TS_NUMBER_OF_CYCLES"
    echo "  TS_SLEEP_TIME:              $TS_SLEEP_TIME"
    echo "  TS_FLAPPING_INTERFACE_LOG_PATH: ${TS_FLAPPING_INTERFACE_LOG_PATH:-/tmp}"
    echo ""
}

# Wait for user confirmation and start logging
wait_confirmation_and_start_logging() {
    read -p "Press enter to continue: "

    # Start logging to file
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1

    echo "=== Flapping Interface Test Started ==="
    echo "Timestamp: $(date)"
    echo "Interface: $TS_INTERFACE_NAME"
    echo "Cycles: $TS_NUMBER_OF_CYCLES"
    echo "Sleep time: $TS_SLEEP_TIME"
    echo "Log path: ${TS_FLAPPING_INTERFACE_LOG_PATH:-/tmp}"
    echo "Log file: $LOG_FILE"
    echo "======================================="
}

# Main flapping loop
run_flapping_test() {
    local interface="$1"
    local cycles="$2"
    local sleep_time="$3"

    for (( c=1; c<=cycles; c++ )); do
        echo "Cycle $c/$cycles"
        echo "Bringing interface $interface down"
        sudo ip link set "$interface" down
        check_interface_state "$interface"
        sleep "$sleep_time"

        echo "Bringing interface $interface up"
        sudo ip link set "$interface" up
        check_interface_state "$interface"
        sleep "$sleep_time"

        date
        echo "-------------------------------------"
    done
}

# Main function
main() {
    echo "Start flapping interface test script..."
    echo -e "${yellow}[WARNING]: This script must be executed on the node where the interface is being disabled(flapping).${normal}"

    # Setup logging
    setup_logging

    # Get all interfaces
    mapfile -t ALL_INTERFACES < <(get_all_interfaces)

    # Set interface name
    TS_INTERFACE_NAME=$(set_interface_name "$1")

    # Validate interface exists
    if ! validate_interface "$TS_INTERFACE_NAME" "${ALL_INTERFACES[@]}"; then
        exit 1
    fi

    # Show initial interface state
    check_interface_state "$TS_INTERFACE_NAME"

    # Display parameters and wait for confirmation
    show_parameters
    wait_confirmation_and_start_logging

    # Run the main flapping test
    run_flapping_test "$TS_INTERFACE_NAME" "$TS_NUMBER_OF_CYCLES" "$TS_SLEEP_TIME"

    echo "=== Flapping Interface Test Finished ==="
    echo "Timestamp: $(date)"
    echo "Log file: $LOG_FILE"
    echo "Finish"
}

# Run main function with all arguments
main "$@"