#!/bin/bash

# Configuration
LOG_FILE="/var/log/disk_check.log"  # Path to log file
DISK="/dev/nvme0n1"                 # Disk to monitor (change to your device)
TEST_DURATION="1s"                  # Duration of each fio test
CHECK_INTERVAL="10"                 # Interval between checks (seconds)

while true; do
    # Get current timestamp for logs
    TIMESTAMP=$(date +"%Y-%m-%d %T")

    # Run fio test with JSON output
    if ! fio --name=healthcheck \
             --filename=$DISK \
             --rw=randread \        # Random read operation
             --bs=4k \              # Block size = 4KB (typical for SSDs)
             --runtime=$TEST_DURATION \
             --time_based \         # Run for specified duration
             --direct=1 \           # Bypass OS cache
             --output-format=json > /tmp/fio_last_test.json 2>&1; then

        # Log error if fio fails
        echo "[$TIMESTAMP] ERROR: Disk $DISK failed!" >> $LOG_FILE
        logger -t disk_check "CRITICAL: Disk $DISK is unavailable!"
    else
        # Extract latency from JSON report (requires 'jq')
        LATENCY=$(jq '.jobs[0].read.lat_ns.mean' /tmp/fio_last_test.json 2>/dev/null)
        echo "[$TIMESTAMP] OK: Disk $DISK latency: $LATENCY ns" >> $LOG_FILE
    fi

    sleep $CHECK_INTERVAL  # Wait before next check
done
