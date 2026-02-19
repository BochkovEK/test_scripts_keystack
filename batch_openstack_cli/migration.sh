#!/bin/bash

# --- CONFIGURATION ---
METRICS_FILE="migration_results.csv"
INTERVAL=5

# --- ARGUMENT PARSING ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --vm-list) VM_LIST="$2"; shift ;;
        --target-host) TARGET_HOST="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$VM_LIST" || -z "$TARGET_HOST" ]]; then
    echo "Usage: $0 --vm-list \"vm1 vm2\" --target-host compute-02"
    exit 1
fi

METRICS_PATH="$(dirname $0)/$METRICS_FILE"
# Header: VM Name, Migration ID, Start Epoch, End Epoch, Duration, Final Status
echo "VM_NAME;MIG_ID;START_TS;END_TS;DURATION;STATUS" > "$METRICS_PATH"

echo "Triggering all migrations for: $VM_LIST"
echo "-----------------------------------------------"

# 1. TRIGGER LOOP: Send all commands immediately
for VM in $VM_LIST; do
    START_TS=$(date +%s)

    # Send migration command to background
    echo "Start migrating $VM..."
    openstack server migrate --live-migration --host "$TARGET_HOST" "$VM" > /dev/null 2>&1 &

    # Capture the migration ID for this specific server
    # We wait a tiny fraction to allow Nova to register the task
    sleep 0.5
    MIG_ID=$(openstack server migration list --server "$VM" -f value -c Id | sort -rn | head -n 1)

    if [[ -z "$MIG_ID" ]]; then
        echo "Warning: Could not find Migration ID for $VM"
        MIG_ID="unknown"
    fi

    echo "${VM};${MIG_ID};${START_TS};pending;0;running" >> "$METRICS_PATH"
    echo "Migration $MIG_ID triggered for $VM"
done

echo "-----------------------------------------------"
echo "All migrations initiated. Monitoring status..."

# 2. MONITORING LOOP
while true; do
    # Get only the lines that are still running
    PENDING_DATA=$(grep ";running" "$METRICS_PATH")

    if [[ -z "$PENDING_DATA" ]]; then
        break
    fi

    while read -r LINE; do
        VM=$(echo "$LINE" | cut -d ';' -f 1)
        MIG_ID=$(echo "$LINE" | cut -d ';' -f 2)
        START_TS=$(echo "$LINE" | cut -d ';' -f 3)

        # Skip if MIG_ID wasn't captured correctly
        [[ "$MIG_ID" == "unknown" ]] && continue

        # Check status using the server-specific migration list
        # We filter by the specific ID we captured earlier
        MIG_STATUS=$(openstack server migration list --server "$VM" -f value | grep "^$MIG_ID " | awk '{print $4}')

        # Terminal statuses in OpenStack: completed, failed, cancelled
        case "$MIG_STATUS" in
            completed|failed|cancelled)
                END_TS=$(date +%s)
                DURATION=$(( END_TS - START_TS ))

                # Update the specific line in the CSV
                sed -i "s|^${VM};${MIG_ID};${START_TS};pending;0;running|${VM};${MIG_ID};${START_TS};${END_TS};${DURATION};${MIG_STATUS}|" "$METRICS_PATH"
                echo "[FINISHED] $VM: $MIG_STATUS in ${DURATION}s"
                ;;
            *)
                # Still running or queuing
                ;;
        esac
    done <<< "$PENDING_DATA"

    REMAINING=$(grep ";running" "$METRICS_PATH" | wc -l)
    echo "Progress: $REMAINING VMs still migrating... ($(date +%T))"

    [[ "$REMAINING" -eq 0 ]] && break
    sleep $INTERVAL
done

echo "-----------------------------------------------"
echo "Work complete. Results saved to $METRICS_PATH"