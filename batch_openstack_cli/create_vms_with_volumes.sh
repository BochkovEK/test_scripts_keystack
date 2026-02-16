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

#!/bin/bash

# --- CONFIGURATION LOADER ---

# Function to get value (Env -> User Input -> Default)
get_param() {
    local var_name=$1
    local prompt_text=$2
    local default_val=$3
    local current_env_val=$(eval echo \$$var_name)

    if [ -n "$current_env_val" ]; then
        # If the variable already exists in the environment (export BASE_NAME=...), we use it
        export "$var_name"="$current_env_val"
    else
        # Otherwise we ask the user
        read -p "$prompt_text [$default_val]: " user_input
        export "$var_name"="${user_input:-$default_val}"
    fi
}

echo "--- Infrastructure Configuration ---"

# Список параметров
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

# --- SUMMARY & CONFIRMATION ---

echo -e "\n========================================"
echo "REVIEW CONFIGURATION:"
echo "========================================"
printf "%-20s : %s\n" "Base Name"      "$BASE_NAME"
printf "%-20s : %s\n" "Flavor"         "$FLAVOR"
printf "%-20s : %s\n" "Image"          "$IMAGE"
printf "%-20s : %s\n" "Network"        "$NET_NAME"
printf "%-20s : %s\n" "Keypair"        "$KEY_PAIR"
printf "%-20s : %s\n" "Sec Group"      "$SEC_GROUP"
printf "%-20s : %s\n" "Host Hint"      "$HOST_HINT"
printf "%-20s : %s\n" "Boot Size"      "${BOOT_SIZE}GB"
printf "%-20s : %s\n" "Data Size"      "${DATA_SIZE}GB x $DATA_COUNT_PER_VM"
printf "%-20s : %s\n" "VM Count"       "$VM_COUNT"
printf "%-20s : %s\n" "Sleep Interval" "${SLEEP_INTERVAL}s"
echo "========================================"

read -p "Press [Enter] to continue or Ctrl+C to abort..."

PHASE=1 # Default phase

# --- ARGUMENT PARSING ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--phase) PHASE="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

echo "Running Phase: $PHASE"

# --- HELPER: GET EXISTING RESOURCES ---
# Snapshot current state to avoid 100+ API calls in loop
EXISTING_VOLS=$(openstack volume list --column Name -f value)
EXISTING_VMS=$(openstack server list --column Name -f value)

# --- PHASE 1: VOLUME CREATION ---
if [ "$PHASE" -eq 1 ]; then
    echo "Starting Volume Creation..."
    for i in $(seq -f "%03g" 1 $VM_COUNT); do
        VM_NAME="${BASE_NAME}-${i}"

        # 1. Boot Volume
        BOOT_VOL="${VM_NAME}-boot"
        if echo "$EXISTING_VOLS" | grep -qxw "$BOOT_VOL"; then
            echo "[Skip] $BOOT_VOL exists"
        else
            echo "[Create] $BOOT_VOL"
            openstack volume create --size $BOOT_SIZE --image "$IMAGE" --bootable "$BOOT_VOL" &
            sleep $SLEEP_INTERVAL
        fi

        # 2. Data Volumes
        for d in $(seq -f "%02g" 1 $DATA_COUNT_PER_VM); do
            DATA_VOL="${VM_NAME}-data-${d}"
            if echo "$EXISTING_VOLS" | grep -qxw "$DATA_VOL"; then
                echo "[Skip] $DATA_VOL exists"
            else
                echo "[Create] $DATA_VOL"
                openstack volume create --size $DATA_SIZE "$DATA_VOL" &
                sleep $SLEEP_INTERVAL
            fi
        done
    done
    echo "Phase 1 complete. Check volumes status before Phase 2."
fi

# --- PHASE 2: VM CREATION ---
if [ "$PHASE" -eq 2 ]; then
    echo "Starting VM Creation..."

    # Disk mapping letters: b, c, d, e... (vdb, vdc, vdd...)
    letters=({b..z})

    for i in $(seq -f "%03g" 1 $VM_COUNT); do
        VM_NAME="${BASE_NAME}-${i}"

        if echo "$EXISTING_VMS" | grep -qxw "$VM_NAME"; then
            echo "[Skip] VM $VM_NAME already exists"
            continue
        fi

        # Build BDM (Block Device Mapping)
        # We use name-based mapping. Note: destination_type=volume is implicit here
        BDM="--block-device-mapping vda=${VM_NAME}-boot:volume"

        for d in $(seq 1 $DATA_COUNT_PER_VM); do
            idx=$((d-1))
            VOL_NAME="${VM_NAME}-data-$(printf "%02d" $d)"
            BDM="$BDM --block-device-mapping vd${letters[$idx]}=$VOL_NAME:volume"
        done

        echo "[Launch] $VM_NAME with BDM..."
        openstack server create \
            --flavor "$FLAVOR" \
            --network "$NET_NAME" \
            --key-name "$KEY_PAIR" \
            --security-group "$SEC_GROUP" \
            --availability-zone "$HOST_HINT" \
            $BDM \
            "$VM_NAME" &

        sleep $SLEEP_INTERVAL
    done
    echo "Phase 2 request burst complete."
fi