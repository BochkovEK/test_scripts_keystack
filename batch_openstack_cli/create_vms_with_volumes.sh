#!/bin/bash

# The script creates a certain number of VMs with a certain number of data disks

# Create key pair
# openstack keypair create test-keypair --public-key ~/test_scripts_keystack/key_test.pub

# Create test security group
# openstack security group create test-security-group
# openstack security group rule create --egress --ethertype IPv4 --protocol tcp test-security-group
# openstack security group rule create --ingress --ethertype IPv4 --protocol tcp test-security-group
# openstack security group rule create --egress --ethertype IPv4 --protocol udp test-security-group
# openstack security group rule create --ingress --ethertype IPv4 --protocol udp test-security-group
# openstack security group rule create --ingress --ethertype IPv4 --protocol icmp test-security-group

# Create env file (.env.create_vms_with_volumes) in script dir or source\define env var
# Example env file .env.create_vms_with_volumes:
#BASE_NAME=test-vm
#FLAVOR=g1-cpu-2-2
#IMAGE=cirros-0.6.3-x86_64-disk
#NET_NAME=pub_net
#KEY_PAIR=test-keypair
#SEC_GROUP=test-security-group
#HOST_HINT=nova:cdm-bl-pca05
#BOOT_SIZE=5
#DATA_SIZE=1
#DATA_COUNT_PER_VM=10
#VM_COUNT=100
#SLEEP_INTERVAL=2

# Add quotas
#openstack quota set --cores -1 $test_project_id --force
#openstack quota set --volumes -1 $test_project_id --force
#openstack quota set --instance -1 $test_project_id --force
#openstack quota set --snapshots -1 $test_project_id --force
#openstack quota set --ram -1 $test_project_id --force

# Create disk from image (create bootable disk)
#openstack volume create --image  ubuntu-22.04-server-cloudimg-amd64.img --size 20 my-volume

# Start
# PHASE 1 - create volumes
# bash ~/test_scripts_keystack/batch_openstack_cli/create_vms_with_volumes.sh
# PHASE 2 - create vms
# bash ~/test_scripts_keystack/batch_openstack_cli/create_vms_with_volumes.sh --phase 2
# PHASE 3 - cleanup
# bash ~/test_scripts_keystack/batch_openstack_cli/create_vms_with_volumes.sh --phase 3

# Remove error volume:
#python ~/test_scripts_keystack/openstack-sdk/set_error_disk.py --force-delete

# Remove volume
#openstack volume delete $(openstack volume list --project <project_name_or_id> -c ID -f value)

# Remove VMs
#openstack server delete $(openstack server list --project test_project -c ID -f value)
#python ~/test_scripts_keystack/openstack-sdk/delete_error_vms.py --force-delete
# or
#for v in test-vm-043 test-vm-044 test-vm-045; do openstack server delete "$v" > /dev/null; sleep 1; done

# Error parse
#grep "2026-02-18" /var/log/kolla/nova/nova-conductor.log | grep -i error

INTERVAL=5

: "${ENV_PATH:=$(dirname $0)/.env.create_vms_with_volumes}"
ENV_FILE=$(basename "${ENV_PATH}" | sed 's/\.[^.]*$//')

VOL_METRICS="volume_metrics_${ENV_FILE}.csv"
VM_METRICS="vm_metrics_${ENV_FILE}.csv"

# Load configuration if file exists
if [ -f "${ENV_PATH}" ]; then
    echo "Loading configuration from ${ENV_PATH}..."
    export $(grep -v '^#' "${ENV_PATH}" | xargs)
fi

get_param() {
    local var_name=$1
    local prompt_text=$2
    local default_val=$3
    local current_val=$(eval echo \$$var_name)
    if [ -z "$current_val" ]; then
        read -p "$prompt_text [$default_val]: " user_input
        export "$var_name"="${user_input:-$default_val}"
    fi
}

echo "Infrastructure Configuration..."
get_param "BASE_NAME"         "Enter Base VM name"          "test-vm"
get_param "FLAVOR"            "Enter Flavor name"           "g1-cpu-2-2"
get_param "IMAGE"             "Enter Image name/ID"         "cirros-0.6.3-x86_64-disk"
get_param "NET_NAME"          "Enter Network name"          "pub_net"
get_param "KEY_PAIR"          "Enter Keypair name"          "test-keypair"
get_param "SEC_GROUP"         "Enter Security Group"        "test_security-group"
get_param "HOST_HINT"         "Enter Target Host (nova:XX)" "nova:compute-01"
get_param "BOOT_SIZE"         "Enter Boot disk size (GB)"   "20"
get_param "DATA_SIZE"         "Enter Data disk size (GB)"   "50"
get_param "DATA_COUNT_PER_VM" "Data disks per VM"           "2"
get_param "VM_COUNT"          "Total VMs to create"         "100"
get_param "SLEEP_INTERVAL"    "Throttling sleep (sec)"      "2"
echo "All required parameters are defined"

echo -e "\n========================================"
echo "REVIEW CONFIGURATION:"
echo "========================================"
cat << EOF
Base Name      : $BASE_NAME
Flavor         : $FLAVOR
Image          : $IMAGE
Network        : $NET_NAME
Keypair        : $KEY_PAIR
Sec Group      : $SEC_GROUP
Host Hint      : $HOST_HINT
Boot Size      : ${BOOT_SIZE}GB
Data Size      : ${DATA_SIZE}GB x $DATA_COUNT_PER_VM
VM Count       : $VM_COUNT
Sleep Interval : ${SLEEP_INTERVAL}s
EOF
echo "========================================"

read -p "Press [Enter] to save config ( $ENV_PATH ) and continue: "

# Save Environment
cat << EOF > $ENV_PATH
BASE_NAME=$BASE_NAME
FLAVOR=$FLAVOR
IMAGE=$IMAGE
NET_NAME=$NET_NAME
KEY_PAIR=$KEY_PAIR
SEC_GROUP=$SEC_GROUP
HOST_HINT=$HOST_HINT
BOOT_SIZE=$BOOT_SIZE
DATA_SIZE=$DATA_SIZE
DATA_COUNT_PER_VM=$DATA_COUNT_PER_VM
VM_COUNT=$VM_COUNT
SLEEP_INTERVAL=$SLEEP_INTERVAL
EOF


PHASE=1
# Parse all arguments first
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--config)
            if [[ -n "$2" && "$2" != -* ]]; then
                ENV_PATH="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        -p|--phase)
            if [[ -n "$2" && "$2" != -* ]]; then
                PHASE="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        *)
            echo "Unknown parameter: $1" >&2
            exit 1
            ;;
    esac
done

# Snapshot state
ENV_FILE=$(basename "${ENV_PATH}" | sed 's/\.[^.]*$//')
EXISTING_VOLS=$(openstack volume list --column Name -f value)
EXISTING_VMS=$(openstack server list --column Name -f value)
#TOTAL_VOLS_EXPECTED=$(( VM_COUNT * (1 + DATA_COUNT_PER_VM) ))

# Load configuration if file exists
if [ -f "${ENV_PATH}" ]; then
    echo "Loading configuration from ${ENV_PATH}..."
    export $(grep -v '^#' "${ENV_PATH}" | xargs)
else
    echo "Config file ${ENV_PATH} not found. Will create a new one."
fi

# --- PHASE 1: VOLUMES ---
if [ "$PHASE" -eq 1 ]; then
    echo "PHASE 1: Creating volumes and logging start times..."
    [ ! -f "$(dirname $0)/$VOL_METRICS" ] && echo "VM_NAME;START_TS;END_TS;DURATION" > "$(dirname $0)/$VOL_METRICS"

    for i in $(seq -f "%03g" 1 $VM_COUNT); do
        VM_NAME="${BASE_NAME}-${i}"
        NEEDS_CREATE=false

        # Logic: If any disk in the pack is missing, we re-log the whole pack start time
        if ! echo "$EXISTING_VOLS" | grep -qxw "${VM_NAME}-boot"; then NEEDS_CREATE=true; fi
        for d in $(seq -f "%02g" 1 $DATA_COUNT_PER_VM); do
            if ! echo "$EXISTING_VOLS" | grep -qxw "${VM_NAME}-data-${d}"; then NEEDS_CREATE=true; fi
        done

        if [ "$NEEDS_CREATE" = true ]; then
            # Cleanup old entry and start new timer
            sed -i "/^${VM_NAME};/d" "$(dirname $0)/$VOL_METRICS"
            echo "${VM_NAME};$(date +%s);pending;0" >> "$(dirname $0)/$VOL_METRICS"

            # Boot Volume
            if ! echo "$EXISTING_VOLS" | grep -qxw "${VM_NAME}-boot"; then
                echo "Start creating ${VM_NAME}-boot..."
                openstack volume create --size $BOOT_SIZE --image "$IMAGE" --bootable "${VM_NAME}-boot" > /dev/null &
                sleep $SLEEP_INTERVAL
            fi
            # Data Volumes
            for d in $(seq -f "%02g" 1 $DATA_COUNT_PER_VM); do
                if ! echo "$EXISTING_VOLS" | grep -qxw "${VM_NAME}-data-${d}"; then
                    echo "Start creating ${VM_NAME}-data-${d}..."
                    openstack volume create --size $DATA_SIZE "${VM_NAME}-data-${d}" > /dev/null &
                    sleep $SLEEP_INTERVAL
                fi
            done
        fi
    done

    echo "Waiting for volumes..."
    while true; do
        CURRENT_LIST=$(openstack volume list --column Name --column Status -f value | grep "^${BASE_NAME}-")
        PENDING_VMS=$(grep ";pending;" "$(dirname $0)/$VOL_METRICS" | cut -d ';' -f 1)

        # Check readiness for pending VMs
        for p_vm in $PENDING_VMS; do
            PACK_STATUS=$(echo "$CURRENT_LIST" | grep "^${p_vm}-")
            # All disks must be available/in-use
            if [[ -n "$PACK_STATUS" ]] && ! echo "$PACK_STATUS" | grep -qvE "available|in-use"; then
                END_TS=$(date +%s)
                START_TS=$(grep "^${p_vm};" "$(dirname $0)/$VOL_METRICS" | cut -d ';' -f 2)
                sed -i "s/^${p_vm};${START_TS};pending;0/${p_vm};${START_TS};${END_TS};$((END_TS - START_TS))/" "$(dirname $0)/$VOL_METRICS"
            fi
        done

        REM_PENDING=$(grep ";pending;" "$(dirname $0)/$VOL_METRICS" | wc -l)
        echo "Volumes Status: $REM_PENDING packs remaining. Time: $(date +%T)"
        if [ "$REM_PENDING" -eq 0 ]; then break; fi
        sleep $INTERVAL
    done
fi

# --- PHASE 2: VMs ---
if [ "$PHASE" -eq 2 ]; then
    echo "PHASE 2: Launching VMs..."
    # Ensure metrics file exists with header
    [ ! -f "$(dirname $0)/$VM_METRICS" ] && echo "VM_NAME;START_TS;END_TS;DURATION" > "$(dirname $0)/$VM_METRICS"

    # Map volume names to IDs for BDM construction
    declare -A VOL_MAP
    while read -r vid vname; do VOL_MAP["$vname"]="$vid"; done < <(openstack volume list --column ID --column Name -f value)

    for i in $(seq -f "%03g" 1 $VM_COUNT); do
        VM_NAME="${BASE_NAME}-${i}"
        if echo "$EXISTING_VMS" | grep -qxw "$VM_NAME"; then continue; fi

        # Initialize tracking with 'pending' status
        sed -i "/^${VM_NAME};/d" "$(dirname $0)/$VM_METRICS"
        echo "${VM_NAME};$(date +%s);pending;0" >> "$(dirname $0)/$VM_METRICS"

        # Build Block Device Mapping (boot + data volumes)
        BOOT_VOL_ID=${VOL_MAP["${VM_NAME}-boot"]}
        BDM="--block-device uuid=${BOOT_VOL_ID},source_type=volume,destination_type=volume,boot_index=0"
        for d in $(seq 1 $DATA_COUNT_PER_VM); do
            VOL_NAME="${VM_NAME}-data-$(printf "%02d" $d)"
            BDM="$BDM --block-device uuid=${VOL_MAP[$VOL_NAME]},source_type=volume,destination_type=volume"
        done

        # Trigger background VM creation
        echo "Start creating $VM_NAME..."
        openstack server create \
            --flavor "$FLAVOR" \
            --network "$NET_NAME" \
            --key-name "$KEY_PAIR" \
            --security-group "$SEC_GROUP" \
            --availability-zone "$HOST_HINT" $BDM "$VM_NAME" > /dev/null &
        sleep $SLEEP_INTERVAL
    done

    echo "Waiting for VMs..."
    while true; do
        # Fetch current statuses and identify pending VMs
        CURRENT_VM_LIST=$(openstack server list --column Name --column Status -f value | grep "^${BASE_NAME}-")
        PENDING_LIST=$(grep ";pending;" "$(dirname $0)/$VM_METRICS" | cut -d ';' -f 1)

        for p_vm in $PENDING_LIST; do
            VM_STATE=$(echo "$CURRENT_VM_LIST" | grep -w "$p_vm" | awk '{print $2}')

            # Finalize metrics if VM reaches terminal state (ACTIVE or ERROR)
            if [[ "$VM_STATE" == "ACTIVE" || "$VM_STATE" == "ERROR" ]]; then
                END_TS=$(date +%s)
                START_TS=$(grep "^${p_vm};" "$(dirname $0)/$VM_METRICS" | cut -d ';' -f 2)
                sed -i "s/^${p_vm};${START_TS};pending;0/${p_vm};${START_TS};${END_TS};$((END_TS - START_TS))/" "$(dirname $0)/$VM_METRICS"
            fi
        done

        # Check if all VMs have exited pending state
        REM_VM=$(grep ";pending;" "$(dirname $0)/$VM_METRICS" | wc -l)
        echo "VM Status: $REM_VM remaining (awaiting ACTIVE or ERROR). Time: $(date +%T)"
        if [ "$REM_VM" -eq 0 ]; then break; fi
        sleep $INTERVAL
    done
fi
# --- PHASE 3: CLEANUP (Teardown Infrastructure) ---
if [ "$PHASE" -eq 3 ]; then
    echo -e "\n========================================"
    echo "PHASE 3: PREPARING CLEANUP"
    echo "========================================"

    # Collect actual resources from OpenStack to show the user
    RESOURCES_VMS=$(openstack server list --column Name -f value | grep "^${BASE_NAME}-")
    RESOURCES_VOLS=$(openstack volume list --column Name -f value | grep "^${BASE_NAME}-")

    VM_COUNT_FOUND=$(echo "$RESOURCES_VMS" | grep -v '^$' | wc -l)
    VOL_COUNT_FOUND=$(echo "$RESOURCES_VOLS" | grep -v '^$' | wc -l)

    if [ "$VM_COUNT_FOUND" -eq 0 ] && [ "$VOL_COUNT_FOUND" -eq 0 ]; then
        echo "No resources found matching prefix '${BASE_NAME}-'. Nothing to delete."
        exit 0
    fi

    echo "The following resources will be DELETED:"
    echo "----------------------------------------"
    [ "$VM_COUNT_FOUND" -gt 0 ] && echo "Virtual Machines ($VM_COUNT_FOUND):" && echo "$RESOURCES_VMS" | sed 's/^/  - /'
    [ "$VOL_COUNT_FOUND" -gt 0 ] && echo "Volumes ($VOL_COUNT_FOUND):" && echo "$RESOURCES_VOLS" | sed 's/^/  - /'
    echo "----------------------------------------"
    echo "WARNING: Metrics files ($VOL_METRICS, $VM_METRICS) will also be cleared."

    read -p "CRITICAL: Press [Enter] to confirm DELETION of all listed resources..."

    # Start cleanup process
    START_CLEANUP=$(date +%s)

    # 0. Clear metrics files immediately
    > "$(dirname $0)/$VOL_METRICS" 2>/dev/null
    > "$(dirname $0)/$VM_METRICS" 2>/dev/null

    # 1. Delete Virtual Machines in background
    if [ "$VM_COUNT_FOUND" -gt 0 ]; then
        echo "Sending delete requests for $VM_COUNT_FOUND VMs..."
        for vm in $RESOURCES_VMS; do
            openstack server delete "$vm" > /dev/null &
            sleep 0.2
        done

        echo "Waiting for VMs to disappear..."
        while true; do
            STILL_VMS=$(openstack server list --column Name -f value | grep "^${BASE_NAME}-" | wc -l)
            echo "Status: $STILL_VMS VMs remaining..."
            if [ "$STILL_VMS" -eq 0 ]; then break; fi
            sleep 5
        done
        echo "All VMs deleted."
    fi

    # 2. Delete Volumes in background
    if [ "$VOL_COUNT_FOUND" -gt 0 ]; then
        echo "Refreshing volume list after VM deletion..."
        # We refresh the list because volumes status might have changed to 'available'
        RESOURCES_VOLS=$(openstack volume list --column Name -f value | grep "^${BASE_NAME}-")
        VOL_COUNT_REFRESHED=$(echo "$RESOURCES_VOLS" | grep -v '^$' | wc -l)

        echo "Sending delete requests for $VOL_COUNT_REFRESHED volumes..."
        for vol in $RESOURCES_VOLS; do
            openstack volume delete "$vol" > /dev/null &
            sleep 0.2
        done

        echo "Waiting for volumes to disappear..."
        while true; do
            STILL_VOLS=$(openstack volume list --column Name -f value | grep "^${BASE_NAME}-" | wc -l)
            echo "Status: $STILL_VOLS volumes remaining..."
            if [ "$STILL_VOLS" -eq 0 ]; then break; fi
            sleep 5
        done
        echo "All volumes deleted."
    fi

    END_CLEANUP=$(date +%s)
    echo -e "\nCleanup complete in $(( END_CLEANUP - START_CLEANUP )) seconds."
fi