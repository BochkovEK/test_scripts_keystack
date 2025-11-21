#!/bin/bash

# Color definitions
normal=$(tput sgr0)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
green=$(tput setaf 2)

# Default values
default_interface_name="eth0"
# In each cycle, shutdown and startup are performed with TWO time_sleep pauses
# The final downtime is calculated using the formula: TS_NUMBER_OF_CYCLES * TS_SLEEP_TIME * 2 (sec)
default_number_of_cycle=35
default_sleep_time=5

# Set parameters from environment or use defaults
[[ -z $TS_NUMBER_OF_CYCLES ]] && TS_NUMBER_OF_CYCLES=$default_number_of_cycle
[[ -z $TS_SLEEP_TIME ]] && TS_SLEEP_TIME=$default_sleep_time
[[ -z $TS_FLAPPING_INTERFACE_LOG_PATH ]] && TS_FLAPPING_INTERFACE_LOG_PATH=""

# Global variable for log file
LOG_FILE=""

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

# Validate interface exists
validate_interface() {
    local interface_name="$1"

    # Check if interface exists using ip command directly
    if ip -o link show "$interface_name" >/dev/null 2>&1; then
        return 0
    else
        echo -e "${red}[ERROR]: Interface $interface_name does not exist!${normal}"
        echo "Available interfaces:"
        ip -o link show | awk -F': ' '{print "  " $2}'
        return 1
    fi
}

# Set interface name from arguments or environment
set_interface_name() {
    local interface_name=""

    # Determine interface name
    if [ -n "$1" ]; then
        interface_name="$1"
        echo "Interface name from argument: '$interface_name'" >&2
    elif [ -n "$TS_INTERFACE_NAME" ]; then
        interface_name="$TS_INTERFACE_NAME"
        echo "Interface name from environment: '$interface_name'" >&2
    else
        interface_name="$default_interface_name"
        echo "Interface name set to default: '$interface_name'" >&2
        echo "Note: Interface name can be defined as argument or TS_INTERFACE_NAME variable" >&2
    fi

    # Remove @ suffix from interface name
    interface_name=${interface_name%%@*}
    echo "$interface_name"  # Clean output for variable assignment
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

# Delayed execution with nohup for background operation
delayed_nohup_execution() {
    local interface="$1"
    local cycles="$2"
    local sleep_time="$3"

    echo -e "\n${yellow}=== ATTENTION: Starting in nohup mode ===${normal}"
    echo "Script will start in background mode after 10 seconds."
    echo "Press Ctrl+C to cancel execution"
    echo ""
    echo "After background startup:"
    echo "  - Script will continue running if SSH connection is lost"
    echo "  - Logs will be written to: $LOG_FILE"
    echo "  - To monitor progress: tail -f $LOG_FILE"
    echo "  - To stop execution: pkill -f \"flapping_interface.sh $interface\""
    echo ""
    echo -e "${yellow}Press Ctrl+C within 10 seconds to cancel...${normal}"

    # Countdown timer
    for i in {10..1}; do
        echo -n "${i}.. "
        sleep 1
    done

    echo -e "\n${green}Starting in background mode...${normal}"

    # Restart script in nohup mode
    exec nohup bash "$0" "$interface" --nohup-mode > "$LOG_FILE" 2>&1 &
    echo "Background process started with PID: $!"
    echo "Log file: $LOG_FILE"
    exit 0
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

    # Check if we are in nohup mode
    if [[ "$2" == "--nohup-mode" ]]; then
        echo "=== Running in nohup mode ==="
        # Skip interactive confirmation in nohup mode
        exec > >(tee -a "$LOG_FILE")
        exec 2>&1
        # Run main test without confirmation
        run_flapping_test "$TS_INTERFACE_NAME" "$TS_NUMBER_OF_CYCLES" "$TS_SLEEP_TIME"
        echo "=== Flapping Interface Test Finished ==="
        echo "Timestamp: $(date)"
        exit 0
    fi

    # Setup logging
    setup_logging

    # Set interface name
    TS_INTERFACE_NAME=$(set_interface_name "$1")

    # Validate interface exists
    if ! validate_interface "$TS_INTERFACE_NAME"; then
        exit 1
    fi

    # Show initial interface state
    check_interface_state "$TS_INTERFACE_NAME"

    # Display parameters
    show_parameters

    # Execution mode selection
    echo -e "\n${yellow}=== Execution Mode Selection ===${normal}"
    echo "1) Interactive mode - will terminate if terminal is closed"
    echo "2) Background mode - will continue running after SSH disconnect"
    read -p "Select mode (1/2) [2]: " mode

    case "${mode:-2}" in
        1)
            # Original interactive mode
            wait_confirmation_and_start_logging
            run_flapping_test "$TS_INTERFACE_NAME" "$TS_NUMBER_OF_CYCLES" "$TS_SLEEP_TIME"
            ;;
        2)
            # Delayed nohup execution
            delayed_nohup_execution "$TS_INTERFACE_NAME" "$TS_NUMBER_OF_CYCLES" "$TS_SLEEP_TIME"
            ;;
        *)
            echo "Invalid selection, using background mode"
            delayed_nohup_execution "$TS_INTERFACE_NAME" "$TS_NUMBER_OF_CYCLES" "$TS_SLEEP_TIME"
            ;;
    esac

    echo "=== Flapping Interface Test Finished ==="
    echo "Timestamp: $(date)"
    echo "Log file: $LOG_FILE"
    echo "Finish"
}

# Run main function with all arguments
main "$@"