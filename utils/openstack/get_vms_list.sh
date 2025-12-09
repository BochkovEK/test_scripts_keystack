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
[[ -z $ANY_STATUS ]] && ANY_STATUS="false"

# Function to display help information
show_help() {
    echo -E "
    Usage: $0 [OPTIONS]

    Options:
      -hv, -hypervisor <name>    Filter by hypervisor name
      -vms <names>               Filter by VM names or IPs (space-separated)
      -p, -project <project>     OpenStack project name (default: all projects)
      -as, --any-status          Show VMs with any status (default: only ACTIVE)
      -debug                     Enable debug output
      --help                     Show this help message

    Output format:
      <vm_name>:<status>:<ip_address>
    NOTE: Only network addresses of the type $IP_REGEX are returned as IP

    Example:
      $0 -hv compute-01 -vms \"vm1 vm2\" -p myproject
    "
}

# Parse command line arguments
parse_arguments() {
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
            -as|--any-status)
                ANY_STATUS="true"
                [ "$TS_DEBUG" = "true" ] && echo "Showing VMs with any status"
                shift
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
}

# Check OpenStack CLI exists
check_openstack_cli() {
    if ! command -v openstack &> /dev/null; then
        echo -e "${red}OpenStack CLI not found${normal}" >&2
        exit 1
    fi
}

# Check jq exists
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${red}jq not found. Please install jq (apt-get install jq / yum install jq)${normal}" >&2
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

# Filter only ACTIVE VMs unless --any-status is specified
filter_active_vms() {
    local input="$1"

    if [[ "$ANY_STATUS" = "true" ]]; then
        # Return all VMs
        echo "$input"
        return 0
    else
        # Filter only ACTIVE
        local active_vms
        active_vms=$(echo "$input" | grep ":ACTIVE:")

        if [[ -z "$active_vms" ]]; then
            echo -e "${yellow}No ACTIVE VMs found${normal}" >&2
            return 1
        fi

        echo "$active_vms"
        return 0
    fi
}

# Main function to get VMs information
get_vms_info() {
    [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Starting get_vms_info function" >&2

    local project_string=""
    if [[ -n "$PROJECT" ]]; then
        project_string="--project $PROJECT"
        [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Using project: $PROJECT" >&2
    else
        project_string="--all-projects"
        [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Using all projects" >&2
    fi

    [ "$TS_DEBUG" = "true" ] && echo "DEBUG: VMS filter: '$VMS'" >&2
    [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Hypervisor filter: '$HYPERVISOR_NAME'" >&2

    # Get all VMs in JSON with only needed columns
    local raw_json
    raw_json=$(openstack server list $project_string --long -f json -c Name -c Status -c Networks -c Host 2>&1)

    if [[ $? -ne 0 ]]; then
        echo -e "${red}ERROR: Failed to get VM list from OpenStack${normal}" >&2
        [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Command output: $raw_json" >&2
        return 1
    fi

    # Check if we have data
    if [[ -z "$raw_json" ]] || [[ "$raw_json" == "[]" ]]; then
        [ "$TS_DEBUG" = "true" ] && echo "DEBUG: No VMs found in project" >&2
        return 1
    fi

    [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Raw JSON received, length: ${#raw_json}" >&2

    # Build jq filter
    local jq_filter=""

    # Start with hypervisor filter if specified
    if [[ -n "$HYPERVISOR_NAME" ]]; then
        jq_filter="(.Host // \"\") == \"$HYPERVISOR_NAME\""
    fi

    # Add VMS filter if specified
    if [[ -n "$VMS" ]]; then
        local vms_filter=""

        # Convert VMS string to array
        local vms_array
        read -ra vms_array <<< "$VMS"

        [ "$TS_DEBUG" = "true" ] && echo "DEBUG: VMS array: ${vms_array[*]}" >&2

        for item in "${vms_array[@]}"; do
            # Check if item looks like an IP address
            if [[ $item =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                # IP address - search in Networks using any() to avoid duplicates
                vms_filter+=" or any(.Networks[]?[]?; .==\"$item\")"
                [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Adding IP filter for: $item" >&2
            else
                # VM name - substring search (case insensitive)
                # Escape special regex characters
                local escaped_item
                escaped_item=$(echo "$item" | sed 's/[][\.*^$()+?{}|]/\\&/g')
                vms_filter+=" or (.Name|test(\"$escaped_item\"; \"i\"))"
                [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Adding name filter for: $item (escaped: $escaped_item)" >&2
            fi
        done

        # Remove leading " or " and wrap in parentheses
        if [[ -n "$vms_filter" ]]; then
            vms_filter="(${vms_filter# or })"

            # Combine with existing filter
            if [[ -n "$jq_filter" ]]; then
                jq_filter="$jq_filter and $vms_filter"
            else
                jq_filter="$vms_filter"
            fi
        fi
    fi

    # If no filters, select all
    if [[ -z "$jq_filter" ]]; then
        jq_filter="true"
    fi

    [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Final jq filter: $jq_filter" >&2

    # Debug: show what jq selects
    if [ "$TS_DEBUG" = "true" ]; then
        echo "DEBUG: Testing jq filter - selected VMs:" >&2
        echo "$raw_json" | jq -r ".[] | select($jq_filter) | \"  - \(.Name) (status: \(.Status))\"" >&2
    fi

    # Process JSON with jq to get final output
    local processed_output
    processed_output=$(echo "$raw_json" | jq -r --arg ip_regex "$IP_REGEX" "
        .[] |
        select($jq_filter) |
        .Name as \$name |
        .Status as \$status |
        (.Networks[\"pub_net\"]? // [])[0] as \$ip |
        if \$ip and (\$ip | test(\$ip_regex)) then
            \"\(\$name):\(\$status):\(\$ip)\"
        else
            \"\(\$name):\(\$status):None\"
        end
    " 2>&1)

    local jq_exit_code=$?

    if [[ $jq_exit_code -ne 0 ]]; then
        echo -e "${red}ERROR: Failed to process JSON with jq${normal}" >&2
        [ "$TS_DEBUG" = "true" ] && echo "DEBUG: jq output: $processed_output" >&2
        return 1
    fi

    # Remove empty lines and check if we have output
    processed_output=$(echo "$processed_output" | grep -v '^$')

    if [[ -z "$processed_output" ]]; then
        [ "$TS_DEBUG" = "true" ] && echo "DEBUG: No VMs matched the filters after formatting" >&2
        return 1
    fi

    [ "$TS_DEBUG" = "true" ] && echo "DEBUG: Processed output lines: $(echo "$processed_output" | wc -l)" >&2

    echo "$processed_output"
    return 0
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Check dependencies
    check_openstack_cli
    check_jq

    # Source OpenRC file
    check_and_source_openrc_file

    # Get VM information
    local output
    output=$(get_vms_info)
    local get_info_exit_code=$?

    if [[ $get_info_exit_code -ne 0 ]] || [[ -z "$output" ]]; then
        exit 1
    fi

    # Filter for ACTIVE VMs unless --any-status is specified
    local filtered_output
    filtered_output=$(filter_active_vms "$output")
    local filter_exit_code=$?

    if [[ $filter_exit_code -ne 0 ]] || [[ -z "$filtered_output" ]]; then
        exit 1
    fi

    # Output the result
    echo "$filtered_output"
}

# Run main function
main "$@"