#!/bin/bash

# Color definitions
normal=$(tput sgr0)
yellow=$(tput setaf 3)
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)

# Default values
default_interface_name="eth0"
default_number_of_cycle=20
default_sleep_time=5

# Set parameters from environment or use defaults
[[ -z $TS_NUMBER_OF_CYCLES ]] && TS_NUMBER_OF_CYCLES=$default_number_of_cycle
[[ -z $TS_SLEEP_TIME ]] && TS_SLEEP_TIME=$default_sleep_time

echo "Start flapping interface test script..."
echo -e "${yellow}[WARNING]: This script must be executed on the node where the interface is being disabled(flapping).${normal}"

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

# Get all interfaces and remove @ suffix if exists
mapfile -t ALL_INTERFACES < <(
    ip -o link show | awk -F': ' '{print $2}' |
    while IFS= read -r iface; do
        echo "${iface%%@*}"
    done
)

# Determine interface name from argument or environment
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

# Verify interface exists in the system
found=false
for item in "${ALL_INTERFACES[@]}"; do
    if [[ "$item" == "$TS_INTERFACE_NAME" ]]; then
        found=true
        break
    fi
done

if [ ! "$found" = true ]; then
    echo -e "${red}[ERROR]: Interface $TS_INTERFACE_NAME does not exist!${normal}"
    echo "Available interfaces:"
    printf '%s\n' "${ALL_INTERFACES[@]}"
    exit 1
fi

# Show initial interface state
check_interface_state "$TS_INTERFACE_NAME"

# Display all available interfaces
echo -e "\nAll available interfaces:"
check_all_interfaces "${ALL_INTERFACES[@]}"

# Confirm parameters before starting
echo -e "\nStart flapping with the following parameters?
  TS_INTERFACE_NAME:    $TS_INTERFACE_NAME
  TS_NUMBER_OF_CYCLES:  $TS_NUMBER_OF_CYCLES
  TS_SLEEP_TIME:        $TS_SLEEP_TIME
"
read -p "Press enter to continue: "

# Main flapping loop
for (( c=1; c<=${TS_NUMBER_OF_CYCLES}; c++ )); do
    echo "Cycle $c/$TS_NUMBER_OF_CYCLES"
    echo "Bringing interface $TS_INTERFACE_NAME down"
    ip link set "$TS_INTERFACE_NAME" down
    check_interface_state "$TS_INTERFACE_NAME"
    sleep "$TS_SLEEP_TIME"

    echo "Bringing interface $TS_INTERFACE_NAME up"
    ip link set "$TS_INTERFACE_NAME" up
    check_interface_state "$TS_INTERFACE_NAME"
    sleep "$TS_SLEEP_TIME"

    date
    echo "-------------------------------------"
done

echo "Finish"