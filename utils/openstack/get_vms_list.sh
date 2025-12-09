#!/bin/bash

# Script to return list of VMs in format: <vm_name>:<status>:<ip>
# Supports filtering by hypervisor and specific VM names

# Color definitions
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
#violet=$(tput setaf 5)

# Script paths
script_file_path=$(realpath "$0")
script_dir=$(dirname "$script_file_path")
parent_dir=$(dirname "$script_dir")
utils_dir="$parent_dir"
check_openrc_script="check_openrc.sh"
default_network_mask="10\.224\.[0-9]{1,3}\.[0-9]{1,3}"

# Default values
#TS_DEBUG="${TS_DEBUG:-false}"
#PROJECT="${PROJECT:-admin}"
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


#get_vms_info() {
#    local project_string=""
#    local vm_name_pattern=""
#    local raw_list=""
#
#    # Build project filter
#    if [[ -n "$PROJECT" ]]; then
#        project_string="--project $PROJECT"
#    else
#        project_string="--all-projects"
#    fi
#
#    # Convert VM names to regex pattern
#    if [[ -n "$VMS" ]]; then
#        vm_name_pattern=$(echo "$VMS" | tr ' ' '|')
#    fi
#
#    # Get and process VM list
#    if [[ -n "$VMS" ]]; then
#        raw_list=$(openstack server list $project_string -f json 2>/dev/null | \
#            jq -r --arg pattern "$vm_name_pattern" '
#                .[] | select(.Name|test($pattern)) |
#                "\(.Name):\(.Status):\(.Networks)"')
#
#    elif [[ -n "$HYPERVISOR_NAME" ]]; then
#        raw_list=$(openstack server list $project_string -f json 2>/dev/null | \
#            jq -r --arg hv "$HYPERVISOR_NAME" '
#                .[] | select(.Host==$hv) |
#                "\(.Name):\(.Status):\(.Networks)"')
#
#    else
#        raw_list=$(openstack server list $project_string -f json 2>/dev/null | \
#            jq -r '.[] | "\(.Name):\(.Status):\(.Networks)"')
#    fi
#
#    # Если список пустой
#    if [[ -z "$raw_list" ]]; then
#        echo -e "${red}No VMs found${normal}" >&2
#        return 1
#    fi
#
#    # Обрабатываем каждую строку: Name:Status:Networks
#    while IFS= read -r line; do
#        [[ -z "$line" ]] && continue
#
#        local vm_name=$(echo "$line" | cut -d: -f1)
#        local status=$(echo "$line" | cut -d: -f2)
#        local networks=$(echo "$line" | cut -d: -f3-)
#
#        # Извлекаем IP из Networks
#        local ip_address=""
#
#        # Пробуем разные форматы Networks
#        # 1. Если это JSON объект (начинается с {)
#        if [[ "$networks" == {* ]]; then
#            ip_address=$(echo "$networks" | jq -r '.[] | .[]' 2>/dev/null | \
#                grep -oE "$IP_REGEX" | head -1)
#        # 2. Если это строка с IP (прямой IP)
#        elif [[ "$networks" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
#            ip_address=$(echo "$networks" | grep -oE "$IP_REGEX" | head -1)
#        # 3. Если это строка формата net=IP
#        else
#            ip_address=$(echo "$networks" | grep -oE "$IP_REGEX" | head -1)
#        fi
#
#        if [[ -n "$ip_address" ]]; then
#            echo "${vm_name}:${status}:${ip_address}"
#        else
#            [ "$TS_DEBUG" = "true" ] && \
#                echo -e "${yellow}No IP found for $vm_name${normal}" >&2
#        fi
#    done <<< "$raw_list"
#}
#
## Function to validate output
#validate_output() {
#    local output="$1"
#    local valid_count=0
#
#    while IFS= read -r line; do
#        if [[ "$line" =~ ^[^:]+:[^:]+:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
#            ((valid_count++))
#        else
#            echo -e "${red}Invalid output format: $line${normal}" >&2
#        fi
#    done <<< "$output"
#
#    if [[ $valid_count -eq 0 ]]; then
#        echo -e "${red}No valid VM entries found${normal}" >&2
#        return 1
#    fi
#}
#
## Main execution
#main() {
#    check_openstack_cli
#    check_jq  # Новая проверка
#    check_and_source_openrc_file
#
#    local output
#    output=$(get_vms_info)
#
#    if [[ $? -eq 0 ]] && [[ -n "$output" ]]; then
#        # Просто выводим результат
#        echo "$output"
#    else
#        exit 1
#    fi
#}
#

get_vms_info() {
    echo "DEBUG: Starting get_vms_info function" >&2

    # Просто получаем все ВМ в JSON и выводим сырые данные
    local raw_json
    raw_json=$(openstack server list --all-projects -f json 2>&1)

    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to get VM list" >&2
        echo "Output: $raw_json" >&2
        return 1
    fi

    echo "DEBUG: Raw JSON length: ${#raw_json}" >&2

    if [[ -z "$raw_json" ]] || [[ "$raw_json" == "[]" ]]; then
        echo "DEBUG: Empty JSON array" >&2
        return 1
    fi

    # Просто выводим сырой JSON через jq для форматирования
    echo "$raw_json" | jq '.'

    return 0
}

main () {
  get_vms_info
}

# Run main function
main