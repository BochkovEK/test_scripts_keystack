#!/bin/bash

# Script for OpenStack volume migration testing with multipath devices
# This script creates VMs, tests volume operations, and performs live migration

# ========== CONSTANTS ==========
FLAVOR="g1-cpu-4-4"
NETWORK="pub_net"
IMAGE="ubuntu-22.04-x64"
SIZE=30
AZ="nova"
NAME_PREFIX="vm_"
MAX_DISKS=10
OUTPUT_PATH="/tmp"

# Host configuration
declare -A HOSTS=(
    [1]="cdm-bl-pca10"
    [2]="cdm-bl-pca11"
)

# Container engine
CONTAINER_ENGINE="podman"

# ========== FUNCTIONS ==========

# Function to create virtual machines
create_vms() {
    echo "Creating virtual machines..."
    declare -A SERVERS

    for i in 1 2; do
        SERVERS[$i]="${NAME_PREFIX}${i}"

        echo "Creating VM: ${SERVERS[$i]} on host: ${HOSTS[$i]}"

        # Build block device parameters
        local block_device_params=""
        for ((n=1; n<=MAX_DISKS; n++)); do
            block_device_params+="--block-device source_type=blank,destination_type=volume,volume_size=${i} "
        done

        # Create server
        openstack server create \
            --flavor "${FLAVOR}" \
            --network "${NETWORK}" \
            --image "${IMAGE}" \
            --boot-from-volume "${SIZE}" \
            ${block_device_params} \
            --availability-zone "${AZ}:${HOSTS[$i]}" \
            "${SERVERS[$i]}"
    done

    # Wait for VMs to be created
    echo "Waiting for VMs to be created..."
    watch -n3 "openstack server list --name ${NAME_PREFIX}"
}

# Function to collect block device information
collect_block_device_info() {
    local stage="$1"
    echo "Collecting block device information (stage: $stage)..."

    for i in 1 2; do
        local server="${NAME_PREFIX}${i}"
        local host="${HOSTS[$i]}"
        local server_id=$(openstack server show -c id -f value "$server")

        # Server information
        openstack server show "$server" | tee "${OUTPUT_PATH}/${server}_server_show_${stage}.txt"

        # Virsh domblklist
        run_remote_command "$host" \
            "sudo $CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id" \
            "${server}_domblklist_${stage}.txt"

        # LSBLK information
        run_remote_command "$host" \
            "sudo $CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
             awk '/dev/{print \$NF}' | xargs -I@ bash -c 'lsblk -np @ | head -1'" \
            "${server}_lsblk_${stage}.txt"

        # Multipath information
        run_remote_command "$host" \
            "sudo $CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
             awk -F- '/by-id/{print \$NF}' | xargs -I@ bash -c 'sudo $CONTAINER_ENGINE exec multipathd multipath -ll @'" \
            "${server}_mpath_${stage}.txt"

        # Device information
        run_remote_command "$host" \
            "sudo $CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
             awk -F- '/by-id/{print \$NF}' | xargs -I@ bash -c 'sudo $CONTAINER_ENGINE exec multipathd multipath -ll @ | tail -1'" \
            "${server}_devs_${stage}.txt"

        # Path information
        run_remote_command "$host" \
            "sudo $CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
             awk -F- '/by-id/{print \$NF}' | xargs -I@ bash -c 'sudo $CONTAINER_ENGINE exec multipathd multipath -ll @ | tail -1 | awk \"{print \\\$3}\" | xargs -I@ bash -c \"ls -l /dev/disk/by-path/* | grep @ | tail -1\"'" \
            "${server}_path_${stage}.txt"
    done

    # Volume information
    for i in 1 2; do
        openstack server volume list "${NAME_PREFIX}${i}" | \
            tee "${OUTPUT_PATH}/${NAME_PREFIX}${i}_volumes_${stage}.txt"
    done
}

# Function to run remote command
run_remote_command() {
    local host="$1"
    local command="$2"
    local output_file="$3"

    bash ~/test_scripts_keystack/command_on_nodes.sh \
        -u kolla \
        -nn "$host" \
        -c "$command" 2>&1 | \
        tee "${OUTPUT_PATH}/${output_file}"
}

# Function to detach and delete volumes
detach_and_delete_volumes() {
    local server="${NAME_PREFIX}1"
    echo "Detaching and deleting volumes for $server..."

    # Stop the server
    openstack server stop "$server"
    echo "Waiting for server to stop..."
    watch -n3 "openstack server list --name $server"

    # Detach non-boot volumes
    openstack server volume list "$server" -c Device -c "Volume ID" -f value | \
        awk '!/vda/{print $2}' | \
        xargs -n1 openstack volume set --detached

    # Verify detachment
    openstack server volume list "$server" -c Device -c "Volume ID" -f value | \
        awk '{print $2}' | \
        xargs -n1 openstack volume show | \
        tee "${OUTPUT_PATH}/${server}_volumes_after_set_detached.txt"

    # Delete detached volumes
    openstack server volume list "$server" -c Device -c "Volume ID" -f value | \
        awk '!/vda/{print $2}' | \
        xargs -n1 openstack volume delete

    # Verify deletion
    openstack server volume list "$server" | \
        tee "${OUTPUT_PATH}/${server}_openstack_server_volume_list_after_delete.txt"
}

# Function to cleanup multipath devices
cleanup_multipath() {
    local host="${HOSTS[1]}"
    local server="${NAME_PREFIX}1"
    local server_id
    server_id=$(openstack server show -c id -f value "$server")

    echo "Cleaning up multipath devices..."

    # Remove multipath devices
    run_remote_command "$host" \
        "sudo $CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
         awk -F- '/by-id/{print \$NF}' | tail -$((MAX_DISKS/2)) | \
         xargs -I@ bash -c 'sudo $CONTAINER_ENGINE exec multipathd multipath -f @'" \
        "${server}_mpath_del.txt"

    # Flush multipath
    run_remote_command "$host" \
        "sudo $CONTAINER_ENGINE exec nova_libvirt virsh domblklist $server_id | \
         awk -F- '/by-id/{print \$NF}' | \
         xargs -I@ bash -c 'sudo $CONTAINER_ENGINE exec multipathd multipath -ll @'" \
        "${server}_mpath_flush.txt"
}

# Function to perform live migration
perform_live_migration() {
    local source_server="${NAME_PREFIX}2"
    local dest_host="${HOSTS[1]}"

    echo "Performing live migration of $source_server to $dest_host..."

    # Perform migration
    openstack server migrate --live "$source_server" --host "$dest_host"

    # Monitor migration status
    echo "Monitoring migration status..."
    watch -n3 "openstack server migration list \
        -c ID -c Created_At -c Updated_At -c Source_Node -c Dest_Node -c Status \
        --server $source_server"

    # Save migration details
    openstack server migration list \
        -c ID -c Created_At -c Updated_At -c Source_Node -c Dest_Node -c Status \
        --server "$source_server" | \
        tee "${OUTPUT_PATH}/openstack_server_migration_list_${source_server}_to_${dest_host}.txt"

    # Check compute logs
    run_remote_command "$dest_host" \
        "sudo grep '$(date +%Y-%m-%d)' /var/log/kolla/nova/nova-compute.log" \
        "nova_compute_log_migrate_${source_server}_to_${dest_host}.txt"

    # Verify server state
    openstack server list --long --name "$NAME_PREFIX" | \
        tee "${OUTPUT_PATH}/openstack_server_list_long_after_migration_${source_server}_to_${dest_host}.txt"
}

# Function to cleanup resources
cleanup_resources() {
    echo "Cleaning up resources..."

    # Delete servers
    for i in 1 2; do
        openstack server delete "${NAME_PREFIX}${i}"
    done

    # Monitor deletion
    watch -n3 "openstack server list --name $NAME_PREFIX -c Name -c Status -c 'Task State'"

    # Additional multipath cleanup
    local host="${HOSTS[1]}"
    run_remote_command "$host" \
        "sudo $CONTAINER_ENGINE exec multipathd multipath -ll 2>&1 | awk '/##/{print \$1}'" \
        "multipath_remaining_devices.txt"
}

# Function to generate final report
generate_report() {
    echo "Generating final report..."

    local files=($(ls -1tr "${OUTPUT_PATH}"/*.txt))
    local report_file="${OUTPUT_PATH}/psi_os-brick2_output.txt"

    echo > "$report_file"  # Clear the file

    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo "# $(basename "$file")" >> "$report_file"
            cat "$file" >> "$report_file"
            echo -e "\n" >> "$report_file"
        fi
    done

    echo "Report generated: $report_file"
}

# ========== MAIN EXECUTION ==========

# Main execution flow
main() {
    echo "Starting OpenStack volume migration test..."

    # Phase 1: Initial setup
    create_vms
    collect_block_device_info "ini"

    # Phase 2: Volume operations
    detach_and_delete_volumes
    cleanup_multipath

    # Phase 3: Migration
    perform_live_migration
    collect_block_device_info "fin"

    # Phase 4: Cleanup and reporting
    cleanup_resources
    generate_report

    echo "Test completed successfully!"
}

# Execute main function
main "$@"