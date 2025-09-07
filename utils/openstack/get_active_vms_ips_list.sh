#!/bin/bash

# Script to return list of VMs in format: <vm_name>:<status>:<ip>
# Supports filtering by hypervisor and specific VM names

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
violet=$(tput setaf 5)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

# Script paths
script_file_path=$(realpath "$0")
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir="$parent_dir"
check_openrc_script="check_openrc.sh"
check_openstack_cli_script="check_openstack_cli.sh"
default_network_mask="10\.224\.[0-9]{1,3}\.[0-9]{1,3}"

# Default values
#TS_DEBUG="${TS_DEBUG:-false}"
#PROJECT="${PROJECT:-admin}"
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $PROJECT ]] && PROJECT=""
[[ -z $VM_NAMES ]] && VM_NAMES=""
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME=""
[[ -z $IP_REGEX ]] && IP_REGEX=$default_network_mask

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -hv, -hypervisor <name>    Filter by hypervisor name
      -n, -vms_name <names>      Filter by VM names (space-separated)
      -p, -project <project>     OpenStack project name (default: $PROJECT)
      -debug                     Enable debug output
      --help                     Show this help message

    Output format:
      <vm_name>:<status>:<ip_address>
    NOTE: Only network addresses of the type $IP_REGEX are returned as IP

    Example:
      $0 -hv compute-01 -n \"vm1 vm2\" -p myproject
    "
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -hv|-hypervisor)
            HYPERVISOR_NAME="$2"
            [ "$TS_DEBUG" = "true" ] && echo "Filtering by hypervisor: $HYPERVISOR_NAME"
            shift 2
            ;;
        -n|-vms_name)
            VM_NAMES="$2"
            [ "$TS_DEBUG" = "true" ] && echo "Filtering by VM names: $VM_NAMES"
            shift 2
            ;;
        -p|-project)
            PROJECT="$2"
            [ "$TS_DEBUG" = "true" ] && echo "Using project: $PROJECT"
            shift 2
            ;;
        -debug)
            TS_DEBUG="true"
            [ "$TS_DEBUG" = "true" ] && echo "Debug mode enabled"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            [ "$TS_DEBUG" = "true" ] && echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Function to check OpenStack CLI availability
check_openstack_cli() {
    if ! bash "$utils_dir/$check_openstack_cli_script" &> /dev/null; then
        echo -e "${red}OpenStack CLI is not available${normal}" >&2
        exit 1
    fi
}

# Function to check and source OpenRC file
check_and_source_openrc_file() {
    if bash "$utils_dir/$check_openrc_script" &> /dev/null; then
        openrc_file=$(bash "$utils_dir/$check_openrc_script")
        source "$openrc_file"
        [ "$TS_DEBUG" = "true" ] && echo "Sourced OpenRC file: $openrc_file"
    else
        bash "$utils_dir/$check_openrc_script"
        exit 1
    fi
}

# Function to get VMs information in required format
get_vms_info() {
    local project_string=""
    local host_string=""
    local vm_name_pattern=""
    local vm_list=""
#    local name_filter_string=""

    # Build filter strings
    [[ -n "$HYPERVISOR_NAME" ]] && host_string="--host $HYPERVISOR_NAME"

    if [[ -n "$PROJECT" ]]; then
        project_string="--project $PROJECT"
    else
        project_string="--all-project"
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]
        PROJECT:          $PROJECT
        HYPERVISOR_NAME:  $HYPERVISOR_NAME
        VM_NAMES:         $VM_NAMES
    "

    # Convert VM names to filter string if provided
    if [[ -n "$VM_NAMES" ]]; then
        # Create regex pattern for multiple names
        vm_name_pattern=$(echo "$VM_NAMES" | tr ' ' '|')
    fi

    # Get VM list with name, status, and networks

    if [[ -n "$VM_NAMES" ]]; then
        # Use grep for multiple name filtering
        [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        Command: openstack server list $project_string $host_string --long -f value -c Name -c Status -c Networks 2>/dev/null | \
            grep -E \"$vm_name_pattern\"
    "
        vm_list=$(openstack server list "$project_string" $host_string --long -f value -c Name -c Status -c Networks 2>/dev/null | \
            grep -E "${vm_name_pattern}")
    else
        [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        Command: openstack server list $project_string $host_string --long -f value -c Name -c Status -c Networks 2>/dev/null
    "
        vm_list=$(openstack server list "$project_string" $host_string --long -f value -c Name -c Status -c Networks 2>/dev/null)
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        vm_list: $vm_list
    "

    if [[ -z "$vm_list" ]]; then
        # Fallback to alternative method if first attempt fails
        [ "$TS_DEBUG" = true ] && echo "Trying alternative method to get VM list"
        vm_list=$(openstack server list $project_string --long -f value -c Name -c Status -c Networks | \
            grep "$HYPERVISOR_NAME" 2>/dev/null)
    fi

    if [[ -z "$vm_list" ]]; then
        echo -e "${red}No VMs found matching criteria${normal}" >&2
        echo -e "${yellow}Project: $PROJECT${normal}" >&2
        echo -e "${yellow}Hypervisor: ${HYPERVISOR_NAME:-any}${normal}" >&2
        echo -e "${yellow}VM names: ${VM_NAMES:-any}${normal}" >&2
        exit 1
    fi

    # Process each VM
    echo "$vm_list" | while read -r vm_name status networks; do
        # Extract IP address from networks field
        local ip_address
        ip_address=$(echo "$networks" | grep -oE "$IP_REGEX" | head -1)

        if [[ -n "$ip_address" ]]; then
            echo "${vm_name}:${status}:${ip_address}"
        else
            [ "$TS_DEBUG" = "true" ] && \
                echo -e "${yellow}Warning: No IP found for VM $vm_name${normal}" >&2
        fi
    done
}

# Function to validate output
validate_output() {
    local output="$1"
    local valid_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[^:]+:[^:]+:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ((valid_count++))
        else
            echo -e "${red}Invalid output format: $line${normal}" >&2
        fi
    done <<< "$output"

    if [[ $valid_count -eq 0 ]]; then
        echo -e "${red}No valid VM entries found${normal}" >&2
        return 1
    fi
}

# Main execution
main() {
    check_openstack_cli
    check_and_source_openrc_file

    local output
    output=$(get_vms_info)

    if [[ $? -eq 0 ]]; then
        if [[ "$TS_DEBUG" = "true" ]]; then
            echo -e "${green}Found VMs:${normal}"
            echo "$output"
        else
            # Validate and output results
            if validate_output "$output"; then
                echo "$output"
            else
                exit 1
            fi
        fi
    else
        exit 1
    fi
}

# Run main function
main