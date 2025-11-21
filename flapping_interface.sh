#!/bin/bash

# Color definitions
normal=$(tput sgr0)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
green=$(tput setaf 2)

# Default values
default_interface_name="eth0"
default_number_of_cycle=60
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

    mkdir -p "$log_path"
    LOG_FILE="${log_path}/flapping_interface_${timestamp}.log"
    echo "Logging output to: $LOG_FILE"
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

# Validate interface exists
validate_interface() {
    local interface_name="$1"

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

    if [ -n "$1" ]; then
        interface_name="$1"
        echo "Interface name from argument: '$interface_name'" >&2
    elif [ -n "$TS_INTERFACE_NAME" ]; then
        interface_name="$TS_INTERFACE_NAME"
        echo "Interface name from environment: '$interface_name'" >&2
    else
        interface_name="$default_interface_name"
        echo "Interface name set to default: '$interface_name'" >&2
    fi

    interface_name=${interface_name%%@*}
    echo "$interface_name"
}

# Auto-restart in background mode after countdown
auto_restart_background() {
    local interface="$1"

    echo -e "\n${yellow}=== Starting in 10 seconds ===${normal}"
    echo "Script will auto-restart in background mode"
    echo "Press Ctrl+C to cancel and run in foreground"
    echo "Log file: $LOG_FILE"
    echo ""

    for i in {10..1}; do
        echo -n "${i}.. "
        sleep 1
    done

    echo -e "\n${green}Restarting in background...${normal}"
    exec nohup bash "$0" "$interface" --background > "$LOG_FILE" 2>&1 &
    echo "Background PID: $!"
    echo "Monitor logs: tail -f $LOG_FILE"
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
    echo "Starting flapping interface test script..."
    echo -e "${yellow}[WARNING]: This script must be executed on the node where the interface is being disabled(flapping).${normal}"

    # Check if we are in background mode
    if [[ "$2" == "--background" ]]; then
        echo "=== Running in background mode ==="
        echo "Interface: $1"
        echo "Cycles: $TS_NUMBER_OF_CYCLES"
        echo "Sleep: $TS_SLEEP_TIME"
        echo "Log: $LOG_FILE"
        echo "=================================="

        # Run the test directly
        run_flapping_test "$1" "$TS_NUMBER_OF_CYCLES" "$TS_SLEEP_TIME"
        echo "=== Test completed ==="
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
    echo -e "\nTest parameters:"
    echo "  Interface: $TS_INTERFACE_NAME"
    echo "  Cycles: $TS_NUMBER_OF_CYCLES"
    echo "  Sleep time: $TS_SLEEP_TIME"
    echo "  Log file: $LOG_FILE"
    echo ""

    # Auto-restart in background after countdown
    auto_restart_background "$TS_INTERFACE_NAME"

    # This point will only be reached if user interrupts the countdown
    echo -e "\n${green}Running in foreground mode...${normal}"
    echo "=== Flapping Interface Test Started ==="

    run_flapping_test "$TS_INTERFACE_NAME" "$TS_NUMBER_OF_CYCLES" "$TS_SLEEP_TIME"

    echo "=== Test completed ==="
}

# Run main function with all arguments
main "$@"