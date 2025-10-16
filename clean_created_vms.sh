#!/bin/bash

# OpenStack VM Cleanup Script
# Removes resources created by create_vms script based on state files

# Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)

# Script directory
script_dir=$(dirname "$0")
cleanup_file=".vm_cleanup_state.env"
utils_dir="$script_dir/utils"
yes_no_answer_script="yes_no_answer.sh"

# External scripts array
external_scripts=(
    "$utils_dir/$yes_no_answer_script"
)

# Default values
[[ -z $AUTO_CONFIRM ]] && AUTO_CONFIRM=false
[[ -z $CLEANUP_ALL ]] && CLEANUP_ALL=true
[[ -z $SPECIFIC_BATCH ]] && SPECIFIC_BATCH=""
[[ -z $TS_DEBUG ]] && TS_DEBUG=false
[[ -z $VIRTUAL_ENV ]] && VIRTUAL_ENV="$script_dir"

declare -gA vm_cache_name=()
declare -gA vm_cache_project=()
declare -gA vm_cache_project_name=()

show_help() {
    echo -E "
    OpenStack VM Cleanup Script

    Usage: $0 [OPTIONS]

    Options:
      -da, -y, -yes     Auto-confirm all actions (no prompts)
      -b, -batch <N>    Cleanup specific batch number (e.g., 1, 2, 3)
      -f, -file <path>  Use custom cleanup state file
      -ef, -envs_folder <path> Use custom folder for environment files
      -debug            Enable debug output
      --help            Show this help message

    Examples:
      $0 -y             # Auto-cleanup all batches (default)
      $0 -batch 2       # Cleanup only batch 2 with confirmation
      $0 -file my_state.env -y  # Use custom state file
      $0 -ef /path/to/configs   # Use custom folder for config files
    "
}

parse_arguments() {
    while [ -n "$1" ]; do
        case "$1" in
            -da|-y|-yes)
                AUTO_CONFIRM=true
                echo "Auto-confirm mode enabled"
                ;;
            -b|-batch)
                SPECIFIC_BATCH="$2"
                CLEANUP_ALL=false
                echo "Cleanup specific batch: $SPECIFIC_BATCH"
                shift
                ;;
            -f|-file)
                cleanup_file="$2"
                echo "Using custom state file: $cleanup_file"
                shift
                ;;
            -ef|-envs_folder)
                VIRTUAL_ENV="$2"
                echo "Using envs config folder: $VIRTUAL_ENV"
                shift
                ;;
            -debug)
                TS_DEBUG=true
                echo "Debug mode enabled"
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown parameter: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

# Function for loading external scripts
load_external_scripts() {
    for script_path in "${external_scripts[@]}"; do
        if [ ! -f "$script_path" ]; then
            echo -e "${red}Error: Required script not found: $script_path${normal}"
            exit 1
        fi
        if [ ! -r "$script_path" ]; then
            echo -e "${red}Error: Script not readable: $script_path${normal}"
            exit 1
        fi
#        echo -e "${blue}Loading external script: $(basename "$script_path")${normal}"
        source "$script_path"
    done
}

# User confirmation function
confirm_action() {
    local message="$1"
    local force_confirm="${2:-true}"

    if [ "$AUTO_CONFIRM" = true ] && [ "$force_confirm" = true ]; then
        echo -e "${green}Auto-confirmed: $message${normal}"
        return 0
    fi

    # Use external confirmation function
    confirm_action_external "$message"
}

# Check and source state file
load_cleanup_state() {
    local state_file_path="$VIRTUAL_ENV/$cleanup_file"

    if [ ! -f "$state_file_path" ]; then
        echo -e "${red}Cleanup state file not found: $state_file_path${normal}"
        exit 1
    fi

    echo -e "${green}Loading cleanup state from: $state_file_path${normal}"

    source "$state_file_path"

    if [ "$TS_DEBUG" = true ]; then
        echo -e "${blue}[DEBUG] Loaded variables:${normal}"
        set | grep -E "^(CREATED_|BATCH_)"
    fi
}

# Get security group details
get_security_group_details() {
    local sg_id="$1"

    # Get security group name
    local sg_name=$(openstack security group show "$sg_id" -c name -f value 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "unknown:unknown"
        return 1
    fi

    # Get security group project
    local sg_project_id=$(openstack security group show "$sg_id" -c project_id -f value 2>/dev/null)

    # Get project name
    local project_name=$(openstack project show "$sg_project_id" -c name -f value 2>/dev/null 2>/dev/null)
    if [ $? -ne 0 ]; then
        project_name="unknown"
    fi

    echo "$sg_name:$project_name"
}

# Check OpenStack CLI
check_openstack_cli() {
    if ! command -v openstack &> /dev/null; then
        echo -e "${red}OpenStack CLI not found${normal}"
        exit 1
    fi
    echo -e "${green}OpenStack CLI is available${normal}"
}

# Single request for all VMs
prefetch_vm_details() {
    echo -e "${blue}Fetching VM details from OpenStack...${normal}"

    # Get all VMs with one request
    local all_vms_data
    all_vms_data=$(openstack server list --all-projects -c ID -c Name -c Project -f value 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$all_vms_data" ]; then
        echo -e "${yellow}Warning: Could not fetch VM list from OpenStack${normal}"
        return 1
    fi

    # Caching data
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local vm_id vm_name project_id
            vm_id=$(echo "$line" | awk '{print $1}')
            vm_name=$(echo "$line" | awk '{print $2}')
            project_id=$(echo "$line" | awk '{print $3}')

            if [ -n "$vm_id" ] && [ "$vm_id" != "null" ]; then
                vm_cache_name["$vm_id"]="$vm_name"
                vm_cache_project["$vm_id"]="$project_id"
            fi
        fi
    done <<< "$all_vms_data"

    echo -e "${blue}Loaded details for ${#vm_cache_name[@]} VMs${normal}"

    # Additionally getting project names
    prefetch_project_details
}

# Caching project names
prefetch_project_details() {
    local unique_projects
    unique_projects=$(printf '%s\n' "${vm_cache_project[@]}" | sort -u | grep -v '^$')

    for project_id in $unique_projects; do
        if [ -n "$project_id" ] && [ "$project_id" != "null" ]; then
            local project_name
            project_name=$(openstack project show "$project_id" -c name -f value 2>/dev/null 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$project_name" ]; then
                vm_cache_project_name["$project_id"]="$project_name"
            else
                vm_cache_project_name["$project_id"]="unknown"
            fi
        fi
    done
}

# Updated VM details retrieval function
get_vm_details_cached() {
    local vm_id="$1"

    local vm_name="${vm_cache_name[$vm_id]}"
    local project_id="${vm_cache_project[$vm_id]}"

    if [ -z "$vm_name" ]; then
        return 1
    fi

    local project_name=""
    if [ -n "$project_id" ]; then
        project_name="${vm_cache_project_name[$project_id]}"
    fi

    # If the project name is not found in the cache, use project_id
    if [ -z "$project_name" ]; then
        project_name="$project_id"
    fi

    echo "$vm_name:$project_name"
}

# Get VM details
get_vm_details() {
    local vm_id="$1"

    # Try cache first
    if [ ${#vm_cache_name[@]} -gt 0 ]; then
        if get_vm_details_cached "$vm_id"; then
            return 0
        fi
    fi

    # Fallback to original logic
    local vm_name=$(openstack server show "$vm_id" -c name -f value 2>/dev/null)
    if [ $? -ne 0 ]; then
        return 1
    fi

    local vm_project_id=$(openstack server show "$vm_id" -c project_id -f value 2>/dev/null)
    local project_name=""

    if [ -n "$vm_project_id" ]; then
        project_name=$(openstack project show "$vm_project_id" -c name -f value 2>/dev/null 2>/dev/null)
    fi

    echo "$vm_name:$project_name"
}

# Collect all resources by category
collect_resources_by_category() {
    local batch_filter="$1"
    local state_file_path="$VIRTUAL_ENV/$cleanup_file"

    # Initialize arrays
    declare -gA all_vms=() all_volumes=() all_security_groups=() all_flavors=() all_keypairs=()

    # Find all batches
    if [ -z "$batch_filter" ]; then
        batches=$(grep -o 'CREATED_VM_IDS_BATCH_[0-9]*' "$state_file_path" | sed 's/CREATED_VM_IDS_BATCH_//' | sort -n)
    else
        batches="$batch_filter"
    fi

    for batch_num in $batches; do
        local vm_ids_var="CREATED_VM_IDS_BATCH_$batch_num"
        local volumes_var="CREATED_BOOT_VOLUMES_BATCH_$batch_num"
        local sg_var="CREATED_SECURITY_GROUP_ID_BATCH_$batch_num"
        local flavor_var="CREATED_FLAVOR_NAME_BATCH_$batch_num"
        local keypair_var="CREATED_KEYPAIR_NAME_USER_BATCH_$batch_num"

        eval "vm_ids=\"\$$vm_ids_var\""
        eval "volumes=\"\$$volumes_var\""
        eval "sg_id=\"\$$sg_var\""
        eval "flavor_name=\"\$$flavor_var\""
        eval "keypair_user=\"\$$keypair_var\""

        # Collect VMs
        if [ -n "$vm_ids" ] && [ "$vm_ids" != "null" ]; then
            for vm_id in $vm_ids; do
                if [ "$vm_id" != "null" ]; then
                    all_vms["$vm_id"]="$batch_num"
                fi
            done
        fi

        # Collect volumes
        if [ -n "$volumes" ] && [ "$volumes" != "null" ]; then
            for volume_id in $volumes; do
                if [ "$volume_id" != "null" ]; then
                    all_volumes["$volume_id"]="$batch_num"
                fi
            done
        fi

        # Collect security groups
        if [ -n "$sg_id" ] && [ "$sg_id" != "null" ]; then
            all_security_groups["$sg_id"]="$batch_num"
        fi

        # Collect flavors
        if [ -n "$flavor_name" ] && [ "$flavor_name" != "null" ]; then
            all_flavors["$flavor_name"]="$batch_num"
        fi

        # Collect keypairs
        if [ -n "$keypair_user" ] && [ "$keypair_user" != "null" ]; then
            all_keypairs["$keypair_user"]="$batch_num"
        fi
    done
}

# Show resources summary by category
show_resources_summary() {
    local batch_info="$1"

    echo -e "${normal}=== CLEANUP SUMMARY $batch_info ===${normal}"

    # VMs summary
    if [ ${#all_vms[@]} -gt 0 ]; then
        echo -e "${normal}VIRTUAL MACHINES (${#all_vms[@]}):${normal}"
        for vm_id in "${!all_vms[@]}"; do
            vm_details=$(get_vm_details "$vm_id")
            if [ $? -eq 0 ]; then
                echo "vm_details: $vm_details"
                vm_name=$(echo "$vm_details" | cut -d: -f1)
                vm_project=$(echo "$vm_details" | cut -d: -f2)
                echo "  - $vm_name (ID: $vm_id, Project: $vm_project) [Batch ${all_vms[$vm_id]}]"
            else
                echo "  - (ID: $vm_id) [Batch ${all_vms[$vm_id]}]"
            fi
        done
        echo ""
    else
        echo -e "${green}No virtual machines found${normal}"
    fi

    # Volumes summary
    if [ ${#all_volumes[@]} -gt 0 ]; then
        echo -e "${normal}VOLUMES (${#all_volumes[@]}):${normal}"
        for volume_id in "${!all_volumes[@]}"; do
            echo "  - $volume_id [Batch ${all_volumes[$volume_id]}]"
        done
        echo ""
    else
        echo -e "${green}No volumes found${normal}"
    fi

    # Security Groups summary
    if [ ${#all_security_groups[@]} -gt 0 ]; then
        echo -e "${normal}SECURITY GROUPS (${#all_security_groups[@]}):${normal}"
        for sg_id in "${!all_security_groups[@]}"; do
            sg_details=$(get_security_group_details "$sg_id")
            sg_name=$(echo "$sg_details" | cut -d: -f1)
            sg_project=$(echo "$sg_details" | cut -d: -f2)
            echo "  - $sg_name (ID: $sg_id, Project: $sg_project) [Batch ${all_security_groups[$sg_id]}]"
        done
        echo ""
    else
        echo -e "${green}No security groups found${normal}"
    fi

    # Keypairs summary
    if [ ${#all_keypairs[@]} -gt 0 ]; then
        echo -e "${normal}KEYPAIRS (${#all_keypairs[@]}):${normal}"
        for keypair_user in "${!all_keypairs[@]}"; do
            key_name="${keypair_user%:*}"
            user_name="${keypair_user#*:}"
            echo "  - $key_name (User: $user_name) [Batch ${all_keypairs[$keypair_user]}]"
        done
        echo ""
    else
        echo -e "${green}No keypairs found${normal}"
    fi

    # Flavors summary
    if [ ${#all_flavors[@]} -gt 0 ]; then
        echo -e "${normal}FLAVORS (${#all_flavors[@]}):${normal}"
        for flavor_name in "${!all_flavors[@]}"; do
            echo "  - $flavor_name [Batch ${all_flavors[$flavor_name]}]"
        done
        echo ""
    else
        echo -e "${green}No flavors found${normal}"
    fi

    echo -e "${normal}===================================${normal}"
}

# Delete resources by category
delete_resources_by_category() {
    local batch_info="$1"

    echo -e "${normal}=== CLEANUP PROCESS $batch_info ===${normal}"

    # 1. Delete all VMs
    if [ ${#all_vms[@]} -gt 0 ]; then
        echo -e "${normal}=== VIRTUAL MACHINES (${#all_vms[@]}) ===${normal}"
        if confirm_action "Delete all virtual machines?"; then
            for vm_id in "${!all_vms[@]}"; do
                echo "Deleting VM: $vm_id [Batch ${all_vms[$vm_id]}]"
                if openstack server delete "$vm_id"; then
                    echo -e "${green}Successfully deleted VM: $vm_id${normal}"
                else
                    echo -e "${red}Failed to delete VM: $vm_id${normal}"
                fi
            done
        else
            echo -e "${yellow}Skipping virtual machines deletion${normal}"
        fi
        echo ""
    fi

    # 2. Delete all volumes
    if [ ${#all_volumes[@]} -gt 0 ]; then
        echo -e "${normal}=== VOLUMES (${#all_volumes[@]}) ===${normal}"
        if confirm_action "Delete all volumes?"; then
            for volume_id in "${!all_volumes[@]}"; do
                echo "Deleting volume: $volume_id [Batch ${all_volumes[$volume_id]}]"
                if openstack volume delete "$volume_id"; then
                    echo -e "${green}Successfully deleted volume: $volume_id${normal}"
                else
                    echo -e "${red}Failed to delete volume: $volume_id${normal}"
                fi
            done
        else
            echo -e "${yellow}Skipping volumes deletion${normal}"
        fi
        echo ""
    fi

    # 3. Delete all security groups
    if [ ${#all_security_groups[@]} -gt 0 ]; then
        echo -e "${normal}=== SECURITY GROUPS (${#all_security_groups[@]}) ===${normal}"
        if confirm_action "Delete all security groups?"; then
            for sg_id in "${!all_security_groups[@]}"; do
                echo "Deleting security group: $sg_id [Batch ${all_security_groups[$sg_id]}]"
                if openstack security group delete "$sg_id"; then
                    echo -e "${green}Successfully deleted security group: $sg_id${normal}"
                else
                    echo -e "${red}Failed to delete security group: $sg_id${normal}"
                fi
            done
        else
            echo -e "${yellow}Skipping security groups deletion${normal}"
        fi
        echo ""
    fi

    # 4. Delete all keypairs
    if [ ${#all_keypairs[@]} -gt 0 ]; then
        echo -e "${normal}=== KEYPAIRS (${#all_keypairs[@]}) ===${normal}"
        if confirm_action "Delete all keypairs?"; then
            for keypair_user in "${!all_keypairs[@]}"; do
                key_name="${keypair_user%:*}"
                echo "Deleting keypair: $key_name [Batch ${all_keypairs[$keypair_user]}]"
                if openstack keypair delete "$key_name"; then
                    echo -e "${green}Successfully deleted keypair: $key_name${normal}"
                else
                    echo -e "${red}Failed to delete keypair: $key_name${normal}"
                fi
            done
        else
            echo -e "${yellow}Skipping keypairs deletion${normal}"
        fi
        echo ""
    fi

    # 5. Delete all flavors
    if [ ${#all_flavors[@]} -gt 0 ]; then
        echo -e "${normal}=== FLAVORS (${#all_flavors[@]}) ===${normal}"
        if confirm_action "Delete all flavors?"; then
            for flavor_name in "${!all_flavors[@]}"; do
                echo "Deleting flavor: $flavor_name [Batch ${all_flavors[$flavor_name]}]"
                if openstack flavor delete "$flavor_name"; then
                    echo -e "${green}Successfully deleted flavor: $flavor_name${normal}"
                else
                    echo -e "${red}Failed to delete flavor: $flavor_name${normal}"
                fi
            done
        else
            echo -e "${yellow}Skipping flavors deletion${normal}"
        fi
        echo ""
    fi
}

# Function to offer cleanup state file removal
offer_cleanup_file_removal() {
    local state_file="$VIRTUAL_ENV/$cleanup_file"

    if [ ! -f "$state_file" ]; then
        return 0
    fi

    echo ""
    echo -e "${normal}=== CLEANUP COMPLETED SUCCESSFULLY ===${normal}"
    echo "Cleanup state file: $state_file"
    echo ""

    if confirm_action "Remove cleanup state file to prevent accidental re-execution?" false; then
        if rm -f "$state_file"; then
            echo -e "${green}Successfully removed state file: $cleanup_file${normal}"
        else
            echo -e "${red}Failed to remove state file: $cleanup_file${normal}"
        fi
    else
        echo -e "${yellow}State file preserved: $cleanup_file${normal}"
        echo "You can use it for future cleanup operations or remove it manually"
    fi
}

# Function to check if all resources were successfully cleaned
check_cleanup_success() {
    # Simple check - if we processed any resources and no critical errors occurred
    local total_resources=0
    total_resources=$(( ${#all_vms[@]} + ${#all_volumes[@]} + ${#all_security_groups[@]} + ${#all_keypairs[@]} + ${#all_flavors[@]} ))

    if [ $total_resources -eq 0 ]; then
        echo -e "${yellow}No resources found to cleanup${normal}"
        return 1
    fi

    return 0
}

# Main cleanup function
main_cleanup() {
    check_openstack_cli
    load_cleanup_state

    load_external_scripts

    # Prefetch VM details for optimization
    if ! prefetch_vm_details; then
        echo -e "${yellow}Warning: Using individual VM queries (optimization failed)${normal}"
    fi

    # Determine batch info for messages
    if [ "$CLEANUP_ALL" = true ]; then
        batch_info="(ALL BATCHES)"
        batch_filter=""
    else
        batch_info="(BATCH $SPECIFIC_BATCH)"
        batch_filter="$SPECIFIC_BATCH"
    fi

    # Collect resources by category
    collect_resources_by_category "$batch_filter"

    # Show summary
    show_resources_summary "$batch_info"

    # Confirm overall cleanup
#    if [ "$AUTO_CONFIRM" = false ]; then
        if ! confirm_action "Proceed with cleanup?" false; then
            echo -e "${yellow}Cleanup cancelled by user${normal}"
            exit 0
        fi
#    fi

    # Delete resources by category
    delete_resources_by_category "$batch_info"

    # Check if cleanup was successful
    if check_cleanup_success; then
        echo -e "${green}Cleanup completed successfully!${normal}"
        # Offer to remove state file
        offer_cleanup_file_removal
    else
        echo -e "${yellow}Cleanup finished with warnings${normal}"
        echo "State file preserved for possible re-execution"
    fi
}

# Run main function
parse_arguments "$@"
main_cleanup