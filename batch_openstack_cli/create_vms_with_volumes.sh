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

# --- 1. LOAD ENV FILE IF EXISTS ---
if [ -f "$ENV_FILE" ]; then
    echo "Loading configuration from $ENV_FILE..."
    # Exporting values from file to current session
    export $(grep -v '^#' $ENV_FILE | xargs)
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
get_param "NET_NAME"          "Enter Network name"          "pubnet"
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

if [ "$PHASE" -eq 1 ]; then
    echo "PHASE 1: Creating Volumes (Errors only)..."
    for i in $(seq -f "%03g" 1 $VM_COUNT); do
        VM_NAME="${BASE_NAME}-${i}"

        # Boot
        if ! echo "$EXISTING_VOLS" | grep -qxw "${VM_NAME}-boot"; then
            openstack volume create --size $BOOT_SIZE --image "$IMAGE" --bootable "${VM_NAME}-boot" > /dev/null &
            sleep $SLEEP_INTERVAL
        fi

        # Data
        for d in $(seq -f "%02g" 1 $DATA_COUNT_PER_VM); do
            VOL_NAME="${VM_NAME}-data-${d}"
            if ! echo "$EXISTING_VOLS" | grep -qxw "$VOL_NAME"; then
                openstack volume create --size $DATA_SIZE "$VOL_NAME" > /dev/null &
                sleep $SLEEP_INTERVAL
            fi
        done

        if (( 10#$i % 10 == 0 )); then echo "Progress: $i/$VM_COUNT VMs processed"; fi
    done
fi

if [ "$PHASE" -eq 2 ]; then
    echo "PHASE 2: Launching VMs (Errors only)..."
    letters=({b..z})
    for i in $(seq -f "%03g" 1 $VM_COUNT); do
        VM_NAME="${BASE_NAME}-${i}"

        if echo "$EXISTING_VMS" | grep -qxw "$VM_NAME"; then continue; fi

        BDM="--block-device-mapping vda=${VM_NAME}-boot:volume"
        for d in $(seq 1 $DATA_COUNT_PER_VM); do
            idx=$((d-1))
            BDM="$BDM --block-device-mapping vd${letters[$idx]}=${VM_NAME}-data-$(printf "%02d" $d):volume"
        done

        openstack server create \
            --flavor "$FLAVOR" \
            --network "$NET_NAME" \
            --key-name "$KEY_PAIR" \
            --security-group "$SEC_GROUP" \
            --availability-zone "$HOST_HINT" $BDM "$VM_NAME" > /dev/null &

        sleep $SLEEP_INTERVAL
        if (( 10#$i % 10 == 0 )); then echo "Progress: $i/$VM_COUNT VM requests sent"; fi
    done
fi