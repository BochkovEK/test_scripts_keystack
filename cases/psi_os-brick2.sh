#!/bin/bash

# Script for OpenStack volume migration testing with multipath devices
# This script creates VMs, tests volume operations, and performs live migration

# ========== CONSTANTS ==========
TC_FLAVOR="${TC_FLAVOR:-"g1-cpu-4-4"}"
TC_NETWORK="${TC_NETWORK:-"pub_net"}"
TC_IMAGE="${TC_IMAGE:-"cirros-0.6.3-x86_64-disk"}"
TC_BOOT_DISK_SIZE="${TC_BOOT_DISK_SIZE:-30}"
TC_AZ="${TC_AZ:-"nova"}"
TC_NAME_PREFIX="${TC_NAME_PREFIX:-"vm_"}"
TC_MAX_DISKS="${TC_MAX_DISKS:-10}"
TC_OUTPUT_PATH="${TC_OUTPUT_PATH:-"/tmp"}"
TC_CONTAINER_ENGINE="${TC_CONTAINER_ENGINE:-"podman"}"
TC_SSH_USER="${TC_SSH_USER:-"kolla"}"
TC_COMMAND_ON_NODES_SCRIPT="${TC_COMMAND_ON_NODES_SCRIPT:-"$HOME/test_scripts_keystack/command_on_nodes.sh"}"
TC_SKIP_STAGE_ENV_FILE="${TC_SKIP_STAGE_ENV_FILE:-"$(dirname "$0")/.skip_stage_envs"}"
#TC_HOSTS must be define by user

# Host configuration
#declare -A HOSTS=(
#    [1]="cdm-bl-pca10"
#    [2]="cdm-bl-pca11"
#)

# ========== FUNCTIONS ==========

# Function to create virtual machines
create_vms() {
    echo "Creating virtual machines..."
    declare -A SERVERS

    for i in 1 2; do
        SERVERS[$i]="${TC_NAME_PREFIX}${i}"

        echo "Creating VM: ${SERVERS[$i]} on host: ${HOSTS[$i]}"

        # Build block device parameters
        local block_device_params=""
        for ((n=1; n<=TC_MAX_DISKS; n++)); do
            block_device_params+="--block-device source_type=blank,destination_type=volume,volume_size=${i} "
        done

        echo "
        openstack server create \
            --flavor \"${TC_FLAVOR}\" \
            --network \"${TC_NETWORK}\" \
            --image \"${TC_IMAGE}\" \
            --boot-from-volume \"${TC_BOOT_DISK_SIZE}\" \
            ${block_device_params} \
            --availability-zone \"${TC_AZ}:${HOSTS[$i]}\" \
            \"${SERVERS[$i]}\"
        "

        read -p "Press Enter to continue: "

        # Create server
        openstack server create \
            --flavor "${TC_FLAVOR}" \
            --network "${TC_NETWORK}" \
            --image "${TC_IMAGE}" \
            --boot-from-volume "${TC_BOOT_DISK_SIZE}" \
            ${block_device_params} \
            --availability-zone "${TC_AZ}:${HOSTS[$i]}" \
            "${SERVERS[$i]}"

        local exit_code=$?

        # Check exit code and output
        if [ $exit_code -ne 0 ]; then
            echo -e "Error: VM \${SERVERS[$i]}: ${SERVERS[$i]}" >&2
            exit 1
        fi
    done

    # Wait for VMs to be created
    echo "Waiting for VMs to be created..."
    watch -n3 "openstack server list --name ${TC_NAME_PREFIX}"

    echo "export SKIP_CREATE_VMS=true" >> "$TC_SKIP_STAGE_ENV_FILE"
    read -p "Press Enter to continue: "
}

# Function to collect block device information
collect_block_device_info() {
    local stage="$1"
    echo "Collecting block device information (stage: $stage)..."

    for i in 1 2; do
        local server="${TC_NAME_PREFIX}${i}"
        local host="${HOSTS[$i]}"
        local server_id
        server_id=$(openstack server show -c id -f value "$server")

        # Server information
        openstack server show "$server" | tee "${TC_OUTPUT_PATH}/${server}_server_show_${stage}.txt"

        # Virsh domblklist
        run_remote_command "$host" \
            "sudo $TC_CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id" \
            "${server}_domblklist_${stage}.txt"

        # LSBLK information
        run_remote_command "$host" \
            "sudo $TC_CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
             awk '/dev/{print \$NF}' | xargs -I@ bash -c 'lsblk -np @ | head -1'" \
            "${server}_lsblk_${stage}.txt"

        # Multipath information
        run_remote_command "$host" \
            "sudo $TC_CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
             awk -F- '/by-id/{print \$NF}' | xargs -I@ bash -c 'sudo $TC_CONTAINER_ENGINE exec multipathd multipath -ll @'" \
            "${server}_mpath_${stage}.txt"

        # Device information
        run_remote_command "$host" \
            "sudo $TC_CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
             awk -F- '/by-id/{print \$NF}' | xargs -I@ bash -c 'sudo $TC_CONTAINER_ENGINE exec multipathd multipath -ll @ | tail -1'" \
            "${server}_devs_${stage}.txt"

        # Path information
        run_remote_command "$host" \
            "sudo $TC_CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
             awk -F- '/by-id/{print \$NF}' | xargs -I@ bash -c 'sudo $TC_CONTAINER_ENGINE exec multipathd multipath -ll @ | tail -1 | awk \"{print \\\$3}\" | xargs -I@ bash -c \"ls -l /dev/disk/by-path/* | grep @ | tail -1\"'" \
            "${server}_path_${stage}.txt"
    done

    # Volume information
    for i in 1 2; do
        openstack server volume list "${TC_NAME_PREFIX}${i}" | \
            tee "${TC_OUTPUT_PATH}/${TC_NAME_PREFIX}${i}_volumes_${stage}.txt"
    done

    if [ "$stage" = ini ]; then
        echo "export SKIP_COLLECT_BLOCK_DEV_INFO_INI=true" >> "$TC_SKIP_STAGE_ENV_FILE"
    else
        echo "export SKIP_COLLECT_BLOCK_DEV_INFO_FIN=true" >> "$TC_SKIP_STAGE_ENV_FILE"
    fi
}

# Function to run remote command
run_remote_command() {
    local host="$1"
    local command="$2"
    local output_file="$3"

    if [ ! -f "$TC_COMMAND_ON_NODES_SCRIPT" ]; then
        echo -e "Error: Script command_on_nodes not found in \$TC_COMMAND_ON_NODES_SCRIPT: $TC_COMMAND_ON_NODES_SCRIPT" >&2
        exit 1
    fi

    bash "$TC_COMMAND_ON_NODES_SCRIPT" \
        -u "$TC_SSH_USER" \
        -nn "$host" \
        -c "$command" 2>&1 | \
        tee "${TC_OUTPUT_PATH}/${output_file}"
}

# Function to detach and delete volumes
detach_and_delete_volumes() {
    local server="${TC_NAME_PREFIX}1"
    echo "Detaching and deleting volumes for $server..."

    # Stop the server
    openstack server stop "$server"
    echo "Waiting for server to stop..."
    watch -n3 "openstack server list --name $server"

    read -p "Press Enter to continue: "

    # Detach non-boot volumes
    openstack server volume list "$server" -c Device -c "Volume ID" -f value | \
        awk '!/vda/{print $2}' | \
        xargs -n1 openstack volume set --detached

    # Verify detachment
    openstack server volume list "$server" -c Device -c "Volume ID" -f value | \
        awk '{print $2}' | \
        xargs -n1 openstack volume show | \
        tee "${TC_OUTPUT_PATH}/${server}_volumes_after_set_detached.txt"

    # Delete detached volumes
    openstack server volume list "$server" -c Device -c "Volume ID" -f value | \
        awk '!/vda/{print $2}' | \
        xargs -n1 openstack volume delete

    # Verify deletion
    openstack server volume list "$server" | \
        tee "${TC_OUTPUT_PATH}/${server}_openstack_server_volume_list_after_delete.txt"

    echo "export SKIP_DETACH_AND_DELETE_VOLUMES=true" >> "$TC_SKIP_STAGE_ENV_FILE"
}

# Function to cleanup multipath devices
cleanup_multipath() {
    local host="${HOSTS[1]}"
    local server="${TC_NAME_PREFIX}1"
    local server_id
    server_id=$(openstack server show -c id -f value "$server")

    echo "Cleaning up multipath devices..."

    # Remove multipath devices
    run_remote_command "$host" \
        "sudo $TC_CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
         awk -F- '/by-id/{print \$NF}' | tail -$((TC_MAX_DISKS/2)) | \
         xargs -I@ bash -c 'sudo $TC_CONTAINER_ENGINE exec multipathd multipath -f @'" \
        "${server}_mpath_del.txt"

    # Flush multipath
    run_remote_command "$host" \
        "sudo $TC_CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
         awk -F- '/by-id/{print \$NF}' | \
         xargs -I@ bash -c 'sudo $TC_CONTAINER_ENGINE exec multipathd multipath -ll @'" \
        "${server}_mpath_flush.txt"

    echo "export SKIP_CLEANUP_MULTIPATH=true" >> "$TC_SKIP_STAGE_ENV_FILE"
}

# Function to perform live migration
perform_live_migration() {
    local source_server="${TC_NAME_PREFIX}2"
    local dest_host="${HOSTS[1]}"

    echo "Performing live migration of $source_server to $dest_host..."

    # Perform migration
    echo "
    openstack server migrate --os-com 2.30 --live \"$source_server\" --host \"$dest_host\"
    "

    read -p "Press Enter to continue: "
    openstack server migrate --os-com 2.30 --live "$source_server" --host "$dest_host"

    # Monitor migration status
    echo "Monitoring migration status..."
    watch -n3 "openstack server migration list \
        -c ID -c Created_At -c Updated_At -c Source_Node -c Dest_Node -c Status \
        --server $source_server"

    read -p "Press Enter to continue: "

    # Save migration details
    openstack server migration list \
        -c ID -c Created_At -c Updated_At -c Source_Node -c Dest_Node -c Status \
        --server "$source_server" | \
        tee "${TC_OUTPUT_PATH}/openstack_server_migration_list_${source_server}_to_${dest_host}.txt"

    # Check compute logs
    run_remote_command "$dest_host" \
        "sudo grep '$(date +%Y-%m-%d)' /var/log/kolla/nova/nova-compute.log" \
        "nova_compute_log_migrate_${source_server}_to_${dest_host}.txt"

    # Verify server state
    openstack server list --long --name "$TC_NAME_PREFIX" | \
        tee "${TC_OUTPUT_PATH}/openstack_server_list_long_after_migration_${source_server}_to_${dest_host}.txt"

    echo "export SKIP_PERFORM_LIVE_MIGR=true" >> "$TC_SKIP_STAGE_ENV_FILE"
}

# Function to cleanup resources
cleanup_resources() {
    echo "Cleaning up resources..."

    # Delete servers
    for i in 1 2; do
        openstack server delete "${TC_NAME_PREFIX}${i}"
    done

    # Monitor deletion
    watch -n3 "openstack server list --name $TC_NAME_PREFIX -c Name -c Status -c 'Task State'"

    read -p "Press Enter to continue: "

    # Additional multipath cleanup
    local host="${HOSTS[1]}"
    run_remote_command "$host" \
        "sudo $TC_CONTAINER_ENGINE exec multipathd multipath -ll 2>&1 | awk '/##/{print \$1}'" \
        "multipath_remaining_devices.txt"

    echo "export SKIP_CLEANUP_RES=true" >> "$TC_SKIP_STAGE_ENV_FILE"
}

# Function to generate final report
generate_report() {
    echo "Generating final report..."

    local files
    local report_file="${TC_OUTPUT_PATH}/psi_os-brick2_output.txt"
    files=($(ls -1tr "${TC_OUTPUT_PATH}"/*.txt))

    echo > "$report_file"  # Clear the file

    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo "# $(basename "$file")" >> "$report_file"
            cat "$file" >> "$report_file"
            echo -e "\n" >> "$report_file"
        fi
    done

    echo "Report generated: $report_file"

    echo "export SKIP_GEN_REPORT=true" >> "$TC_SKIP_STAGE_ENV_FILE"
}

# Validate hosts
validate_hosts () {
    # Host configuration from environment variable
    if [ -z "${TC_HOSTS}" ]; then
        echo "Error: TC_HOSTS environment variable is not set"
        echo "Please set TC_HOSTS variable with space-separated host names:"
        echo "export TC_HOSTS=\"host_name1 host_name2\""
        exit 1
    fi

    # Declare associative array (if using bash 4+)
    declare -g -a HOSTS

    # Convert TC_HOSTS string to array with numeric indices starting from 1
    IFS=' ' read -ra HOSTS_TMP <<< "${TC_HOSTS}"

    local index=1
    for host in "${HOSTS_TMP[@]}"; do
        HOSTS[$index]="$host"
        ((index++))
    done

    HOSTS_COUNT=${#HOSTS_TMP[@]}

    # Validate hosts count
    if [ "$HOSTS_COUNT" -lt 2 ]; then
        echo "Error: TC_HOSTS must contain at least 2 host names"
        echo "Current value: ${TC_HOSTS}"
        exit 1
    fi

    echo "Using hosts: ${HOSTS[*]}"
    echo "Host count: ${HOSTS_COUNT}"
}

# Get ssh user
get_ssh_user () {
    if [[ -z "$TC_SSH_USER" ]]; then
        echo -e "Error: Failed to determine SSH user!" >&2
        exit 1
    fi
}

# Output variable
output_variables () {
  echo "
  TC_FLAVOR: ${TC_FLAVOR}
  TC_NETWORK: ${TC_NETWORK}
  TC_IMAGE: ${TC_IMAGE}
  TC_BOOT_DISK_SIZE: ${TC_BOOT_DISK_SIZE}
  TC_AZ: ${TC_AZ}
  TC_NAME_PREFIX: ${TC_NAME_PREFIX}
  TC_MAX_DISK: ${TC_MAX_DISKS}
  TC_OUTPUT_PATH: ${TC_OUTPUT_PATH}
  TC_CONTAINER_ENGINE: ${TC_CONTAINER_ENGINE}
  TC_SSH_USER: ${TC_SSH_USER}
  TC_COMMAND_ON_NODES_SCRIPT: ${TC_COMMAND_ON_NODES_SCRIPT}
  TC_HOSTS: ${TC_HOSTS}
    HOSTS: ${HOSTS[*]}
  "
  read -p "Press Enter to continue: "
}

# Source skip envs
source_env () {
  if [ -f "$TC_SKIP_STAGE_ENV_FILE" ]; then
      echo "Source 'skip envs' file $TC_SKIP_STAGE_ENV_FILE exists"
      echo "cat..."
      cat $TC_SKIP_STAGE_ENV_FILE
      read -p "Press Enter to continue: "
      source "$TC_SKIP_STAGE_ENV_FILE"
  else
      echo "Source 'skip envs' file not $TC_SKIP_STAGE_ENV_FILE exists"
      read -p "Press Enter to continue: "
  fi
}

# ========== MAIN EXECUTION ==========

# Main execution flow
main() {
    echo "Starting OpenStack volume migration test..."

    # Validate hosts
    validate_hosts

    #Get ssh user
    get_ssh_user

    #Output variables
    output_variables

    # Source skip envs
    source_env

    # Phase 1: Initial setup
    [ ! "${SKIP_CREATE_VMS}" = true ] && create_vms
    [ ! "${SKIP_COLLECT_BLOCK_DEV_INFO_INI}" = true ] && collect_block_device_info "ini"

    # Phase 2: Volume operations
    [ ! "${SKIP_DETACH_AND_DELETE_VOLUMES}" = true ] && detach_and_delete_volumes
    [ ! "${SKIP_CLEANUP_MULTIPATH}" = true ] && cleanup_multipath

    # Phase 3: Migration
    [ ! "${SKIP_PERFORM_LIVE_MIGR}" = true ] && perform_live_migration
    [ ! "${SKIP_COLLECT_BLOCK_DEV_INFO_FIN}" = true ] && collect_block_device_info "fin"

    # Phase 4: Cleanup and reporting
    [ ! "${SKIP_CLEANUP_RES}" = true ] && cleanup_resources
    [ ! "${SKIP_GEN_REPORT}" = true ] && generate_report

    echo "Test completed successfully!"
}

# Execute main function
main "$@"