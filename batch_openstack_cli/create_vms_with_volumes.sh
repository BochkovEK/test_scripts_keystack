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


ENV_FILE=".env.create_vms_with_volumes"
# -- Waiter parm --
TIMEOUT=3600  # 1 hour in seconds
INTERVAL=5
# -----------------



# --- 1. LOAD ENV FILE IF EXISTS ---
if [ -f "$(dirname $0)/$ENV_FILE" ]; then
    echo "Loading configuration from $ENV_FILE..."
    # Exporting values from file to current session
    export $(grep -v '^#' $(dirname $0)/$ENV_FILE | xargs)
fi

get_param() {
    local var_name=$1
    local prompt_text=$2
    local default_val=$3
    # Look for value in Environment (already loaded from .env or set manually)
    local current_val=$(eval echo \$$var_name)

    if [ -z "$current_val" ]; then
        read -p "$prompt_text [$default_val]: " user_input
        export "$var_name"="${user_input:-$default_val}"
    fi
}

echo "--- Infrastructure Configuration ---"

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

read -p "Press [Enter] to save config and continue..."

# Save current variables to .env file for future use
cat << EOF > $ENV_FILE
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
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--phase) PHASE="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Snapshot current state
echo "Fetching current OpenStack state..."
EXISTING_VOLS=$(openstack volume list --column Name -f value)
EXISTING_VMS=$(openstack server list --column Name -f value)

TOTAL_VOLS=$(( VM_COUNT * (1 + DATA_COUNT_PER_VM) ))

if [ "$PHASE" -eq 1 ]; then
    CURRENT_VOL=0
    echo "PHASE 1: Creating $TOTAL_VOLS volumes in total (skipping existing)..."

    for i in $(seq -f "%03g" 1 $VM_COUNT); do
        VM_NAME="${BASE_NAME}-${i}"

        # --- 1. Boot Volume ---
        ((CURRENT_VOL++))
        if ! echo "$EXISTING_VOLS" | grep -qxw "${VM_NAME}-boot"; then
            echo "Start creating ${VM_NAME}-boot"
            openstack volume create --size $BOOT_SIZE --image "$IMAGE" --bootable "${VM_NAME}-boot" > /dev/null &
            sleep $SLEEP_INTERVAL
        fi

        # Display progress after processing boot volume
        if (( CURRENT_VOL % 10 == 0 || CURRENT_VOL == TOTAL_VOLS )); then
            echo "Progress: $CURRENT_VOL / $TOTAL_VOLS volumes processed"
        fi

        # --- 2. Data Volumes ---
        for d in $(seq -f "%02g" 1 $DATA_COUNT_PER_VM); do
            ((CURRENT_VOL++))
            VOL_NAME="${VM_NAME}-data-${d}"
            if ! echo "$EXISTING_VOLS" | grep -qxw "$VOL_NAME"; then
                echo "Start creating ${VOL_NAME}"
                openstack volume create --size $DATA_SIZE "$VOL_NAME" > /dev/null &
                sleep $SLEEP_INTERVAL
            fi

            # Display progress after each data volume
            if (( CURRENT_VOL % 10 == 0 || CURRENT_VOL == TOTAL_VOLS )); then
                echo "Progress: $CURRENT_VOL / $TOTAL_VOLS volumes processed"
            fi
        done
    done
    # --- Start of Waiter Block ---
    echo -e "\nAll requests sent. Starting Waiter (Timeout: 1h, Interval: 5s)..."

    START_TIME=$(date +%s)

    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$(( CURRENT_TIME - START_TIME ))

        # Fetch current statuses for volumes matching our BASE_NAME
        # We only need Name and Status to minimize API load
        CURRENT_STATE=$(openstack volume list --column Name --column Status -f value | grep "^${BASE_NAME}")

        READY_COUNT=$(echo "$CURRENT_STATE" | grep -w "available" | wc -l)
        ERROR_COUNT=$(echo "$CURRENT_STATE" | grep -w "error" | wc -l)
        TOTAL_TERMINAL=$(( READY_COUNT + ERROR_COUNT ))

        # Log progress to console
        echo "Status: Total terminal states $TOTAL_TERMINAL / $TOTAL_VOLS (Ready: $READY_COUNT, Errors: $ERROR_COUNT). Elapsed: ${ELAPSED}s"

        # Condition 1: Success or complete processing
        if [ "$TOTAL_TERMINAL" -ge "$TOTAL_VOLS" ]; then
            echo -e "\n[Success] All volumes have reached a terminal state."
            break
        fi

        # Condition 2: Timeout
        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            echo -e "\n[Timeout] Reached 1 hour limit. Not all volumes are ready."
            break
        fi

        sleep $INTERVAL
    done

    # Final reporting
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "------------------------------------------------"
        echo "CRITICAL: The following volumes are in ERROR state:"
        echo "$CURRENT_STATE" | grep -w "error"
        echo "------------------------------------------------"
        echo "Please fix these errors before proceeding to Phase 2."
    else
        echo "Perfect! All volumes are in 'available' state. You can safely start Phase 2."
    fi
    # --- End of Waiter Block ---
fi

# --- PHASE 2: VMs (UUID-safe version) ---
if [ "$PHASE" -eq 2 ]; then
    echo "PHASE 2: Launching $VM_COUNT Virtual Machines..."
    letters=({b..z})

    echo "Caching Volume UUIDs..."
    declare -A VOL_MAP
    # Get all volumes and their IDs at once
    while read -r vid vname; do
        VOL_MAP["$vname"]="$vid"
    done < <(openstack volume list --column ID --column Name -f value)

    for i in $(seq -f "%03g" 1 $VM_COUNT); do
        VM_NAME="${BASE_NAME}-${i}"

        if echo "$EXISTING_VMS" | grep -qxw "$VM_NAME"; then continue; fi

        # 1. Resolve Boot Volume UUID
        BOOT_VOL_NAME="${VM_NAME}-boot"
        BOOT_VOL_ID=${VOL_MAP["$BOOT_VOL_NAME"]}

        if [ -z "$BOOT_VOL_ID" ]; then
            echo "[Error] Could not find UUID for $BOOT_VOL_NAME. Skipping..."
            continue
        fi

        # 2. Build BDM using UUIDs instead of Names
        BDM="--block-device uuid=${BOOT_VOL_ID},source_type=volume,destination_type=volume,disk_bus=virtio,boot_index=0"

        for d in $(seq 1 $DATA_COUNT_PER_VM); do
            idx=$((d-1))
            DATA_VOL_NAME="${VM_NAME}-data-$(printf "%02d" $d)"
            DATA_VOL_ID=${VOL_MAP["$DATA_VOL_NAME"]}

            if [ -n "$DATA_VOL_ID" ]; then
                BDM="$BDM --block-device uuid=${DATA_VOL_ID},source_type=volume,destination_type=volume,disk_bus=virtio"
            fi
        done

        # 3. Create Server
        openstack server create \
            --flavor "$FLAVOR" \
            --network "$NET_NAME" \
            --key-name "$KEY_PAIR" \
            --security-group "$SEC_GROUP" \
            --availability-zone "$HOST_HINT" \
            $BDM \
            "$VM_NAME" > /dev/null &

        sleep $SLEEP_INTERVAL
        [[ $i == *0 ]] && echo "Progress: $i / $VM_COUNT VM launch requests sent"
    done
fi