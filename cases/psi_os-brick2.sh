#!/bin/bash

# Script for OpenStack volume migration testing with multipath devices
# This script creates VMs, tests volume operations, and performs live migration

# Предпроверка podman exec -it multipathd multipath -ll (на гиперах)
# Итоговая проверка dmesg -T (на гиперах)

#ENVS
#export SKIP_CREATE_VMS=true
#export SKIP_COLLECT_BLOCK_DEV_INFO_INI=true
#export SKIP_DETACH_AND_DELETE_VOLUMES=true
#export SKIP_CLEANUP_MULTIPATH=true
#export SKIP_LIVE_MIGR=true
#export SKIP_COLLECT_BLOCK_DEV_INFO_FIN=true
#export SKIP_CLEANUP_RES=true
#export SKIP_GEN_REPOR=true
#export TC_SERVERS=""
#export TC_HOSTS=""

script_dir=$(dirname "$0")
utils_dir="$script_dir/../utils"
get_nodes_list_script="get_nodes_list.sh"
default_flavor_name="psi_os-break2"
default_flavor_vcpus=4
default_flavor_ram=4096

# ========== CONSTANTS ==========
TC_FLAVOR="${TC_FLAVOR:-""}"
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
TC_SERVERS="${TC_SERVERS:-""}"
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

    read -p "Press Enter to continue: "

#    declare -A SERVERS

    if [ -z "$TC_FLAVOR" ]; then
        openstack flavor create --public --vcpus "$default_flavor_vcpus" --ram "$default_flavor_ram" --disk 0 "$default_flavor_name"
        TC_FLAVOR="$default_flavor_name"
    fi

    for i in 1 2; do
#        [ -z "$TC_SERVERS" ] && SERVERS[$i]="${TC_NAME_PREFIX}${i}"

        echo "Creating VM: ${SERVERS[$i]} on host: ${HOSTS[$i]}"

        # Build block device parameters
        # for the first VM volume size 1 GB, for the second 2 GB
        local block_device_params=""
        for ((n=1; n<=TC_MAX_DISKS; n++)); do
            block_device_params+="--block-device source_type=blank,destination_type=volume,volume_size=${i} "
        done

        echo "Check vms"
        vm_exist=$(openstack server list |grep -E "${SERVERS[$i]}.*ACTIVE")

        if [ -z "$vm_exist" ]; then

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
        fi
    done

    # Wait for VMs to be created
    echo "Waiting for VMs to be created..."
    watch -n3 "openstack server list"
#    --name ${TC_NAME_PREFIX}"

    echo "export SKIP_CREATE_VMS=true" >> "$TC_SKIP_STAGE_ENV_FILE"

}

# Function to collect block device information
collect_block_device_info() {
    local stage="$1"
    echo "Collecting block device information (stage: $stage)..."

    read -p "Press Enter to continue: "

    for i in 1 2; do
        local server="${SERVERS[$i]}"
        local host="${HOSTS[$i]}"
        local server_id
        server_id=$(openstack server show -c id -f value "$server")

        # Server information
        openstack server show "$server" | tee "${TC_OUTPUT_PATH}/${server}_server_show_${stage}.txt"

        # Volume information
        openstack server volume list "${SERVERS[$i]}" | \
            tee "${TC_OUTPUT_PATH}/${SERVERS[$i]}_volumes_${stage}.txt"

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

    echo "
    Execute command: $command on host: $host and output to output_file: $output_file ...
    "

#    read -p "Press Enter to continue: "

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
    local server="${SERVERS[1]}"
    echo "Detaching and deleting volumes for $server..."

    read -p "Press Enter to continue: "

    echo "Powering off VM: $server"
    # Stop the server
    openstack server stop "$server"
    echo "Waiting for server to stop..."
    watch -n3 "openstack server list --name $server"

    echo "Detach non-boot volumes..."
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
    local server="${SERVERS[1]}"
    local server_id
    server_id=$(openstack server show -c id -f value "$server")

    echo "Cleaning up multipath devices..."

    read -p "Press Enter to continue: "

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

# Function live migration
perform_live_migration() {
    local source_server="${SERVERS[2]}"
    local dest_host="${HOSTS[1]}"

    echo "Live migration of $source_server to $dest_host..."

    read -p "Press Enter to continue: "

    # Migration
    echo "
    openstack server migrate --os-com 2.87 --live \"$source_server\" --host \"$dest_host\"
    "

    read -p "Press Enter to continue: "
    openstack server migrate --os-com 2.87 --live "$source_server" --host "$dest_host" --debug

    # Monitor migration status
    echo "Monitoring migration status..."
    watch -n3 "openstack server migration list \
        -c ID -c Created_At -c Updated_At -c Source_Node -c Dest_Node -c Status \
        --server $source_server"

    # Save migration details
    openstack server migration list \
        -c ID -c Created_At -c Updated_At -c Source_Node -c Dest_Node -c Status \
        --server "$source_server" | \
        tee "${TC_OUTPUT_PATH}/openstack_server_migration_list_${source_server}_to_${dest_host}.txt"

    echo "Get nova_compute_logs from ${dest_host}..."
    read -p "Press Enter to continue: "

    # Check compute logs
    run_remote_command "$dest_host" \
        "sudo grep '$(date +%Y-%m-%d)' /var/log/kolla/nova/nova-compute.log" \
        "nova_compute_log_migrate_${source_server}_to_${dest_host}.txt"

    echo "Check server list..."
    read -p "Press Enter to continue: "

    # Verify server state
    openstack server list --long -c id -c Host -c Status -c state -c Name -c "Power State" -c networks -c flavor -c availability_zone -c pinned_availability_zone | \
        tee "${TC_OUTPUT_PATH}/openstack_server_list_long_after_migration_${source_server}_to_${dest_host}.txt"

    echo "export SKIP_LIVE_MIGR=true" >> "$TC_SKIP_STAGE_ENV_FILE"
}

# Function to cleanup resources
cleanup_resources() {
    echo "Cleaning up resources..."

    local host
    local pair_host
    local ip_host

    # Delete servers
    if [ -z "$TC_SERVERS" ]; then
        echo "Delete vms ${SERVERS[*]}"
        read -p "Press Enter to continue: "
        for i in 1 2; do
            openstack server delete "${SERVERS[$i]}"
        done
        # Monitor deletion
        watch -n3 "openstack server list -c Name -c Status -c 'Task State'"
#       --name $TC_NAME_PREFIX
    fi

    if [ -n "$TC_FLAVOR" ]; then
        echo "Delete flavor ${TC_FLAVOR}"
        read -p "Press Enter to continue: "
        openstack flavor delete "$TC_FLAVOR"
    fi

    echo "Additional multipath cleanup..."
    read -p "Press Enter to continue: "

    # Additional multipath cleanup
    host="${HOSTS[1]}"

    if [ -f $utils_dir/$get_nodes_list_script ]; then
        pair_host="$(bash $utils_dir/$get_nodes_list_script -nn $host)"
       if [[ -n "$pair_host" && "$pair_host" != *ERROR* ]]; then
            ip_host="${pair_host#*:}"
            multipath_with_sharp_string="$(ssh $TC_SSH_USER@$ip_host "sudo podman exec multipathd multipath -ll 2>&1 | awk '/##/{print\$1}'")"
            for i in $multipath_with_sharp_string; do
                ssh $TC_SSH_USER@$ip_host "sudo $TC_CONTAINER_ENGINE exec multipathd dmsetup message $i 0 fail_if_no_path && sudo $TC_CONTAINER_ENGINE exec multipathd multipath -f $i"
            done
            fault_dev_multipath=$(ssh $TC_SSH_USER@$ip_host "sudo podman exec multipathd multipath -ll | awk '/fault/{print\$3}'")
            for dev in $fault_dev_multipath; do
                ssh $TC_SSH_USER@$ip_host "sudo sh -c 'echo 1 > /sys/block/$dev/device/delete'"
            done
            for i in $multipath_with_sharp_string; do
                ssh $TC_SSH_USER@$ip_host "sudo podman exec multipathd dmsetup message $i 0 fail_if_no_path && sudo podman exec multipathd multipath -f $i; sudo dmsetup remove -f $i"
            done
        fi
    else
        echo "Script $utils_dir/$get_nodes_list_script not found. Multipath cleanup not completed"
    fi

#    echo "export SKIP_CLEANUP_RES=true" >> "$TC_SKIP_STAGE_ENV_FILE"
}

# Function to generate final report
generate_report() {
    echo "Generating final report..."

    read -p "Press Enter to continue: "

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

# Get servers
get_servers () {

    # Declare associative array (if using bash 4+)
    declare -g -a SERVERS

    if [ -n "${TC_SERVERS}" ]; then
        # Convert TC_HOSTS string to array with numeric indices starting from 1
        IFS=' ' read -ra SERVERS_TMP <<< "${TC_SERVERS}"

        local index=1
        for srv in "${SERVERS_TMP[@]}"; do
            SERVERS[$index]="$srv"
            ((index++))
        done

        SRV_COUNT=${#SERVERS_TMP[@]}
    else
        echo "TC_SERVERS not defined, generating server names from prefix"

        # Use default naming pattern
        for i in 1 2; do
            SERVERS[$i]="${TC_NAME_PREFIX}${i}"
        done

        SRV_COUNT=2
    fi

    # Validate srv count
    if [ "$SRV_COUNT" -lt 2 ]; then
        echo "Error: TC_SERVERS must contain at least 2 srv names"
        echo "Current value: ${TC_SERVERS}"
        exit 1
    fi

    echo "Using servers: ${SERVERS[*]}"
    echo "servers count: ${SRV_COUNT}"
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
  TC_SERVERS: ${TC_SERVERS}
    SERVERS: ${SERVERS[*]}
  "

}

# Source skip envs
source_env () {
  if [ -f "$TC_SKIP_STAGE_ENV_FILE" ]; then
      echo "Source 'skip envs' file $TC_SKIP_STAGE_ENV_FILE exists"
      echo "cat..."
      cat $TC_SKIP_STAGE_ENV_FILE

      source "$TC_SKIP_STAGE_ENV_FILE"
  else
      echo "Source 'skip envs' file not $TC_SKIP_STAGE_ENV_FILE exists"

  fi
}

# ========== MAIN EXECUTION ==========

# Main execution flow
main() {
    echo "Starting OpenStack volume migration test..."

    # Source skip envs
    source_env

    # Validate hosts
    validate_hosts

    #Get servers
    get_servers

    #Get ssh user
    get_ssh_user

    #Output variables
    output_variables

    # Phase 1: Initial setup
    [ ! "${SKIP_CREATE_VMS}" = true ] && create_vms
    [ ! "${SKIP_COLLECT_BLOCK_DEV_INFO_INI}" = true ] && collect_block_device_info "ini"

    # Phase 2: Volume operations
    [ ! "${SKIP_DETACH_AND_DELETE_VOLUMES}" = true ] && detach_and_delete_volumes
    [ ! "${SKIP_CLEANUP_MULTIPATH}" = true ] && cleanup_multipath

    # Phase 3: Migration
    [ ! "${SKIP_LIVE_MIGR}" = true ] && perform_live_migration
    [ ! "${SKIP_COLLECT_BLOCK_DEV_INFO_FIN}" = true ] && collect_block_device_info "fin"

    # Phase 4: Cleanup and reporting
    [ ! "${SKIP_CLEANUP_RES}" = true ] && cleanup_resources
    [ ! "${SKIP_GEN_REPORT}" = true ] && generate_report

    echo "Test completed successfully!"
}

# Execute main function
main "$@"