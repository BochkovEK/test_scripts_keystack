#!/bin/bash

# OpenStack VM Cleanup Script
# Removes resources created by create_vms script based on state files

# Script directory
script_dir=$(dirname "$0")
cleanup_file=".vm_cleanup_state.env"

# Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
normal=$(tput sgr0)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)

# Default values
AUTO_CONFIRM=false
CLEANUP_ALL=true
SPECIFIC_BATCH=""
TS_DEBUG=false

show_help() {
    echo -E "
    OpenStack VM Cleanup Script

    Usage: $0 [OPTIONS]

    Options:
      -y, -yes          Auto-confirm all actions (no prompts)
      -b, -batch <N>    Cleanup specific batch number (e.g., 1, 2, 3)
      -f, -file <path>  Use custom cleanup state file
      -debug            Enable debug output
      --help            Show this help message

    Examples:
      $0 -y             # Auto-cleanup all batches (default)
      $0 -batch 2       # Cleanup only batch 2 with confirmation
      $0 -file my_state.env -y  # Use custom state file
    "
}

parse_arguments() {
    while [ -n "$1" ]; do
        case "$1" in
            -y|-yes)
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

# User confirmation function
confirm_action() {
    local message="$1"

    if [ "$AUTO_CONFIRM" = true ]; then
        echo -e "${green}Auto-confirmed: $message${normal}"
        return 0
    fi

    while true; do
        read -p "$message [y/N]: " yn
        case $yn in
            [Yy]* )
                echo -e "${green}Confirmed${normal}"
                return 0
                ;;
            [Nn]* | "" )
                echo -e "${yellow}Skipped${normal}"
                return 1
                ;;
            * )
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Check and source state file
load_cleanup_state() {
    if [ ! -f "$script_dir/$cleanup_file" ]; then
        echo -e "${red}Cleanup state file not found: $cleanup_file${normal}"
        exit 1
    fi

    echo -e "${green}Loading cleanup state from: $cleanup_file${normal}"
    source "$script_dir/$cleanup_file"

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

# Delete VMs
delete_vms() {
    local vm_ids="$1"
    local batch_info="$2"

    if [ -z "$vm_ids" ] || [ "$vm_ids" = "null" ]; then
        echo -e "${yellow}No VMs to delete in $batch_info${normal}"
        return 0
    fi

    echo -e "${orange}Deleting VMs from $batch_info...${normal}"

    for vm_id in $vm_ids; do
        if [ "$vm_id" != "null" ]; then
            if confirm_action "Delete VM $vm_id"; then
                echo "Deleting VM: $vm_id"
                if openstack server delete $vm_id; then
                    echo -e "${green}Successfully deleted VM: $vm_id${normal}"
                else
                    echo -e "${red}Failed to delete VM: $vm_id${normal}"
                fi
            fi
        fi
    done
}

# Delete volumes
delete_volumes() {
    local volume_ids="$1"
    local batch_info="$2"

    if [ -z "$volume_ids" ] || [ "$volume_ids" = "null" ]; then
        echo -e "${yellow}No volumes to delete in $batch_info${normal}"
        return 0
    fi

    echo -e "${orange}Deleting volumes from $batch_info...${normal}"

    for volume_id in $volume_ids; do
        if [ "$volume_id" != "null" ]; then
            if confirm_action "Delete volume $volume_id"; then
                echo "Deleting volume: $volume_id"
                if openstack volume delete $volume_id; then
                    echo -e "${green}Successfully deleted volume: $volume_id${normal}"
                else
                    echo -e "${red}Failed to delete volume: $volume_id${normal}"
                fi
            fi
        fi
    done
}

# Delete keypair
delete_keypair() {
    local keypair_user_var="$1"
    local batch_info="$2"

    if [ -z "$keypair_user_var" ] || [ "$keypair_user_var" = "null" ]; then
        echo -e "${yellow}No keypair to delete in $batch_info${normal}"
        return 0
    fi

    if confirm_action "Delete keypair: $keypair_user_var"; then
        local key_name="${keypair_user_var%:*}"
        echo "Deleting keypair: $key_name"
        if openstack keypair delete "$key_name"; then
            echo -e "${green}Successfully deleted keypair: $key_name${normal}"
        else
            echo -e "${red}Failed to delete keypair: $key_name${normal}"
        fi
    else
        echo -e "${yellow}Skipping keypair deletion in $batch_info${normal}"
    fi
}

# Delete security group
delete_security_group() {
    local sg_id="$1"
    local batch_info="$2"

    if [ -z "$sg_id" ] || [ "$sg_id" = "null" ]; then
        echo -e "${yellow}No security group to delete in $batch_info${normal}"
        return 0
    fi

    # Get security group details for confirmation message
    sg_details=$(get_security_group_details "$sg_id")
    sg_name=$(echo "$sg_details" | cut -d: -f1)
    sg_project=$(echo "$sg_details" | cut -d: -f2)

    local confirmation_message="Delete security group: $sg_name (ID: $sg_id, Project: $sg_project)"

    if confirm_action "$confirmation_message"; then
        echo "Deleting security group: $sg_id"
        if openstack security group delete "$sg_id"; then
            echo -e "${green}Successfully deleted security group: $sg_name${normal}"
        else
            echo -e "${red}Failed to delete security group: $sg_name${normal}"
        fi
    else
        echo -e "${yellow}Skipping security group deletion in $batch_info${normal}"
    fi
}

# Delete flavor
delete_flavor() {
    local flavor_name="$1"
    local batch_info="$2"

    if [ -z "$flavor_name" ] || [ "$flavor_name" = "null" ]; then
        echo -e "${yellow}No flavor to delete in $batch_info${normal}"
        return 0
    fi

    if confirm_action "Delete flavor: $flavor_name"; then
        echo "Deleting flavor: $flavor_name"
        if openstack flavor delete "$flavor_name"; then
            echo -e "${green}Successfully deleted flavor: $flavor_name${normal}"
        else
            echo -e "${red}Failed to delete flavor: $flavor_name${normal}"
        fi
    else
        echo -e "${yellow}Skipping flavor deletion in $batch_info${normal}"
    fi
}

# Display batch summary
show_batch_summary() {
    local batch_num="$1"
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

    echo -e "${blue}Batch $batch_num:${normal}"

    if [ -n "$vm_ids" ] && [ "$vm_ids" != "null" ]; then
        vm_count=$(echo $vm_ids | wc -w)
        echo "  VMs: $vm_count"
    fi

    if [ -n "$volumes" ] && [ "$volumes" != "null" ]; then
        volume_count=$(echo $volumes | wc -w)
        echo "  Volumes: $volume_count"
    fi

    if [ -n "$sg_id" ] && [ "$sg_id" != "null" ]; then
        sg_details=$(get_security_group_details "$sg_id")
        sg_name=$(echo "$sg_details" | cut -d: -f1)
        sg_project=$(echo "$sg_details" | cut -d: -f2)
        echo "  Security Group: $sg_name (Project: $sg_project)"
    fi

    if [ -n "$flavor_name" ] && [ "$flavor_name" != "null" ]; then
        echo "  Flavor: $flavor_name"
    fi

    if [ -n "$keypair_user" ] && [ "$keypair_user" != "null" ]; then
        echo "  Keypair: $keypair_user"
    fi
}

# Cleanup specific batch - ALL resources
cleanup_batch() {
    local batch_num="$1"
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

    if [ -z "$vm_ids" ] && [ -z "$sg_id" ] && [ -z "$flavor_name" ] && [ -z "$keypair_user" ]; then
        echo -e "${yellow}No resources found for batch $batch_num${normal}"
        return 0
    fi

    echo -e "${orange}=== Cleaning up Batch $batch_num ===${normal}"

    # Delete ALL resources in the batch
    delete_vms "$vm_ids" "Batch $batch_num"
    delete_volumes "$volumes" "Batch $batch_num"
    delete_security_group "$sg_id" "Batch $batch_num"
    delete_flavor "$flavor_name" "Batch $batch_num"
    delete_keypair "$keypair_user" "Batch $batch_num"
}

# Main cleanup function
main_cleanup() {
    check_openstack_cli
    load_cleanup_state

    echo -e "${orange}=== CLEANUP SUMMARY ===${normal}"

    if [ "$CLEANUP_ALL" = true ]; then
        # Find all batches
        batches=$(grep -o 'CREATED_VM_IDS_BATCH_[0-9]*' "$script_dir/$cleanup_file" | sed 's/CREATED_VM_IDS_BATCH_//' | sort -n)
        echo "Cleaning up ALL batches:"
        for batch_num in $batches; do
            show_batch_summary "$batch_num"
        done
    elif [ -n "$SPECIFIC_BATCH" ]; then
        echo "Cleaning up specific batch:"
        show_batch_summary "$SPECIFIC_BATCH"
    fi

    echo -e "${orange}========================${normal}"

    # Confirm overall cleanup
    if [ "$AUTO_CONFIRM" = false ]; then
        if ! confirm_action "Proceed with cleanup?"; then
            echo -e "${yellow}Cleanup cancelled by user${normal}"
            exit 0
        fi
    fi

    # Cleanup batches
    if [ "$CLEANUP_ALL" = true ]; then
        # Find all batches
        batches=$(grep -o 'CREATED_VM_IDS_BATCH_[0-9]*' "$script_dir/$cleanup_file" | sed 's/CREATED_VM_IDS_BATCH_//' | sort -n)
        for batch_num in $batches; do
            cleanup_batch "$batch_num"
        done
    elif [ -n "$SPECIFIC_BATCH" ]; then
        cleanup_batch "$SPECIFIC_BATCH"
    else
        echo -e "${yellow}No cleanup action specified${normal}"
        exit 1
    fi

    echo -e "${green}Cleanup completed!${normal}"
}

# Run main function
parse_arguments "$@"
main_cleanup