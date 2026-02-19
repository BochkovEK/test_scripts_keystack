#!/bin/bash

# --- CONFIGURATION ---
METRICS_FILE="migration_metrics.csv"
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
echo "VM_NAME;MIGRATION_ID;START_TS;END_TS;DURATION;STATUS" > "$METRICS_PATH"

echo "Phase 1: Triggering Migrations..."
for VM in $VM_LIST; do
    START_TS=$(date +%s)

    # Trigger migration
    openstack server migrate --live-migration --host "$TARGET_HOST" "$VM" > /dev/null 2>&1 &

    # Give Nova a split second to create the migration record
    sleep 0.5

    # Get the latest Migration ID for this server
    MIG_ID=$(openstack server migration list "$VM" -f value -c Id | sort -rn | head -n 1)

    echo "${VM};${MIG_ID};${START_TS};pending;0;running" >> "$METRICS_PATH"
    echo "Migration $MIG_ID started for $VM"
done

echo "-----------------------------------------------"
echo "Phase 2: Monitoring Migration Tasks..."

while true; do
    PENDING_LINES=$(grep ";running" "$METRICS_PATH")

    if [[ -z "$PENDING_LINES" ]]; then
        break
    fi

    while read -r LINE; do
        VM=$(echo "$LINE" | cut -d ';' -f 1)
        MIG_ID=$(echo "$LINE" | cut -d ';' -f 2)
        START_TS=$(echo "$LINE" | cut -d ';' -f 3)

        # Check specific migration status
        # Statuses: running, completed, failed, cancelled
        MIG_STATUS=$(openstack server migration show "$VM" "$MIG_ID" -f value -c status)

        if [[ "$MIG_STATUS" == "completed" || "$MIG_STATUS" == "failed" || "$MIG_STATUS" == "cancelled" ]]; then
            END_TS=$(date +%s)
            DURATION=$(( END_TS - START_TS ))

            # Update CSV
            sed -i "s|^${VM};${MIG_ID};${START_TS};pending;0;running|${VM};${MIG_ID};${START_TS};${END_TS};${DURATION};${MIG_STATUS}|" "$METRICS_PATH"
            echo "[TERMINAL] $VM -> $MIG_STATUS (${DURATION}s)"
        fi
    done <<< "$PENDING_LINES"

    REMAINING=$(grep ";running" "$METRICS_PATH" | wc -l)
    echo "Waiting for $REMAINING migrations... ($(date +%T))"

    [ "$REMAINING" -eq 0 ] && break
    sleep $INTERVAL
done

echo "-----------------------------------------------"
echo "Results saved to $METRICS_PATH"