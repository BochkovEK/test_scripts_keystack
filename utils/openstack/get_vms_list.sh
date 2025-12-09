#!/bin/bash

# Script to return list of VMs in format: <vm_name>:<status>:<ip>
# Supports filtering by hypervisor and specific VM names

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)

# Script paths
script_file_path=$(realpath "$0")
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir="$parent_dir"
check_openrc_script="check_openrc.sh"
default_network_mask="10\.224\.[0-9]{1,3}\.[0-9]{1,3}"

# Default values
[[ -z $TS_DEBUG ]] && TS_DEBUG="false"
[[ -z $PROJECT ]] && PROJECT=""
[[ -z $VMS ]] && VMS=""
[[ -z $HYPERVISOR_NAME ]] && HYPERVISOR_NAME=""
[[ -z $IP_REGEX ]] && IP_REGEX=$default_network_mask

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -hv, -hypervisor <name>    Filter by hypervisor name
      -vms <names\ip>      Filter by VM names (space-separated)
      -p, -project <project>     OpenStack project name (default: all projects)
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
        -vms)
            VMS="$2"
            [ "$TS_DEBUG" = "true" ] && echo "Filtering by VM: $VMS"
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

# Check OpenStack CLI
check_openstack_cli () {
    if ! command -v openstack &> /dev/null; then
        echo -e "${red}OpenStack CLI not found${normal}"
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
    local vm_name_pattern=""
    local vm_list=""
    local grep_pattern=""

    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]
        PROJECT:          $PROJECT
        HYPERVISOR_NAME:  $HYPERVISOR_NAME
        VMS:              $VMS
    "

    # Build project filter
    if [[ -n "$PROJECT" ]]; then
        project_string="--project $PROJECT"
    else
        project_string="--all-projects"
    fi

    # Convert VM names to filter string if provided
    if [[ -n "$VMS" ]]; then
        # Create regex pattern for multiple names
        vm_name_pattern=$(echo "$VMS" | tr ' ' '|')
    fi

    # Get VM list with name, status, and networks
    if [[ -n "$VMS" ]]; then
        # Filter by VM names
        [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        Command: openstack server list $project_string --long -f value -c Name -c Status -c Networks -c Host 2>/dev/null | \
            grep -E \"$vm_name_pattern\"
    "
        vm_list=$(openstack server list $project_string --long -f value -c Name -c Status -c Networks -c Host 2>/dev/null | \
            grep -E "${vm_name_pattern}")

    elif [[ -n "$HYPERVISOR_NAME" ]]; then
        # Filter by hypervisor only
        [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        Command: openstack server list $project_string --long -f value -c Name -c Status -c Networks -c Host 2>/dev/null | \
            grep \"$HYPERVISOR_NAME\"
    "
        vm_list=$(openstack server list $project_string --long -f value -c Name -c Status -c Networks -c Host 2>/dev/null | \
            grep "$HYPERVISOR_NAME")

    else
        # Get all VMs (no filtering)
        [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        Command: openstack server list $project_string --long -f value -c Name -c Status -c Networks -c Host 2>/dev/null
    "
        vm_list=$(openstack server list $project_string --long -f value -c Name -c Status -c Networks -c Host 2>/dev/null)
    fi

    [ "$TS_DEBUG" = "true" ] && echo -e "
    [DEBUG]:
        Raw VM list count: $(echo "$vm_list" | wc -l)
    "

    if [[ -z "$vm_list" ]]; then
        echo -e "${red}No VMs found matching criteria${normal}" >&2
        echo -e "${yellow}Project: ${PROJECT:-all projects}${normal}" >&2
        echo -e "${yellow}Hypervisor: ${HYPERVISOR_NAME:-any}${normal}" >&2
        echo -e "${yellow}VM names: ${VMS:-any}${normal}" >&2
        return 1
    fi

    # Process each VM
    echo "$vm_list" | while IFS= read -r line; do
        # Extract fields from the line
        local vm_name status networks host
        vm_name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $2}')
        # Networks field might contain spaces, so we need to handle it carefully
        # Get everything from position 3 to the end
        networks=$(echo "$line" | awk '{for(i=3;i<=NF-1;i++) printf $i " "; print ""}' | sed 's/ $//')

        # Extract IP address from networks field
        local ip_address
        ip_address=$(echo "$networks" | grep -oE "$IP_REGEX" | head -1)

        if [[ -n "$ip_address" ]]; then
            echo "${vm_name}:${status}:${ip_address}"
        else
            [ "$TS_DEBUG" = "true" ] && \
                echo -e "${yellow}Warning: No IP found for VM $vm_name (status: $status)${normal}" >&2
        fi
    done
}

# Function to validate output
validate_output() {
    local output="$1"
    local valid_count=0

    if [[ -z "$output" ]]; then
        echo -e "${red}No output generated${normal}" >&2
        return 1
    fi

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

    if [[ $? -eq 0 ]] && [[ -n "$output" ]]; then
        if [[ "$TS_DEBUG" = "true" ]]; then
            echo -e "${green}Found VMs:${normal}"
            echo "$output"
            echo -e "${green}Total: $(echo "$output" | wc -l) VMs${normal}"
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